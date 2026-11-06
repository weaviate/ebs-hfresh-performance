terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = var.project
      Owner   = "benchmark-operator"
      Purpose = "blog-benchmark"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------- network

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = var.project }
}

# Public subnet holds only the NAT gateway and the Instance Connect Endpoint.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availability_zone
  tags              = { Name = "${var.project}-public" }
}

# Both instances live here: no public IPv4, egress through the NAT gateway.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zone
  tags              = { Name = "${var.project}-private" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project}-nat" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${var.project}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# S3 traffic (results bucket, bundle sync) bypasses the NAT gateway: free and faster.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# No ingress from outside the VPC. Shell access goes through the Instance Connect Endpoint only.
resource "aws_security_group" "client" {
  name   = "${var.project}-client"
  vpc_id = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "server" {
  name   = "${var.project}-server"
  vpc_id = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "server_from_client" {
  for_each                     = toset(["8080", "50051", "2112", "6060"])
  security_group_id            = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.client.id
}

# EC2 Instance Connect Endpoint: SSH tunnelled over the AWS API (HTTPS), no public ingress needed.
resource "aws_security_group" "eice" {
  name   = "${var.project}-eice"
  vpc_id = aws_vpc.main.id
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_ec2_instance_connect_endpoint" "eice" {
  subnet_id          = aws_subnet.public.id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false
  tags               = { Name = "${var.project}-eice" }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_eice" {
  for_each                     = { server = aws_security_group.server.id, client = aws_security_group.client.id }
  security_group_id            = each.value
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.eice.id
}

# ---------------------------------------------------------------- iam / ssm

resource "aws_iam_role" "instance" {
  name = "${var.project}-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_ro" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role_policy" "instance_inline" {
  name = "${var.project}-inline"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeVolumes", "ec2:DescribeVolumesModifications", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.results.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.results.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project}-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------- results bucket

resource "aws_s3_bucket" "results" {
  bucket        = "${var.project}-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------- data volume

resource "aws_ebs_volume" "data" {
  count             = var.data_disk == "ebs" ? 1 : 0
  availability_zone = var.availability_zone
  size              = var.data_volume_size_gib
  type              = "gp3"
  iops              = var.data_volume_iops
  throughput        = var.data_volume_throughput
  encrypted         = true
  tags              = { Name = "${var.project}-data" }

  # IOPS / throughput are changed live with `aws ec2 modify-volume` during the
  # experiment. Terraform must not fight those changes.
  lifecycle {
    ignore_changes = [iops, throughput]
  }
}

# ---------------------------------------------------------------- server

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.server_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  availability_zone           = var.availability_zone
  vpc_security_group_ids      = [aws_security_group.server.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  ebs_optimized               = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/user-data-server.sh", {
    data_disk        = var.data_disk
    volume_id        = var.data_disk == "ebs" ? aws_ebs_volume.data[0].id : "none"
    results_bucket   = aws_s3_bucket.results.bucket
    weaviate_version = var.weaviate_version
  })

  tags = { Name = "${var.project}-server" }
}

resource "aws_volume_attachment" "data" {
  count                          = var.data_disk == "ebs" ? 1 : 0
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.data[0].id
  instance_id                    = aws_instance.server.id
  stop_instance_before_detaching = true
}

# ---------------------------------------------------------------- client

resource "aws_instance" "client" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.client_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  availability_zone           = var.availability_zone
  vpc_security_group_ids      = [aws_security_group.client.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 120
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/user-data-client.sh", {
    server_private_ip = aws_instance.server.private_ip
    dataset_url       = var.dataset_url
    results_bucket    = aws_s3_bucket.results.bucket
  })

  tags = { Name = "${var.project}-client" }
}
