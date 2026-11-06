variable "region" {
  type    = string
  default = "us-east-2"
}

variable "availability_zone" {
  type    = string
  default = "us-east-2a"
}

variable "project" {
  type    = string
  default = "ebs-hfresh-blog"
}

variable "server_instance_type" {
  description = "Must have an instance-level EBS cap above 80k IOPS / 2,000 MiB/s. c6in.8xlarge = 100k IOPS / 3,125 MB/s."
  type        = string
  default     = "c6in.8xlarge"
}

variable "client_instance_type" {
  type    = string
  default = "c7i.2xlarge"
}

variable "data_volume_size_gib" {
  description = "gp3 needs >= 160 GiB to allow 80,000 IOPS (500 IOPS per GiB)."
  type        = number
  default     = 400
}

variable "data_volume_iops" {
  description = "Initial IOPS. Created at max so the import is fast; modified down via CLI before phase 1."
  type        = number
  default     = 80000
}

variable "data_volume_throughput" {
  description = "Initial throughput in MiB/s. The AWS provider still validates <= 1000; the volume is raised to 2000 with `aws ec2 modify-volume` right after apply (ignore_changes covers it)."
  type        = number
  default     = 1000
}

variable "dataset_url" {
  type    = string
  default = "https://storage.googleapis.com/ann-datasets/custom/sphere-10M-meta-dpr.hdf5"
}

variable "weaviate_version" {
  type    = string
  default = "1.39.3"
}

variable "admin_cidrs" {
  description = "Operator public IPs (/32) allowed to SSH directly. Empty list disables the rules; the EICE path works regardless."
  type        = list(string)
  default     = []
}

variable "data_disk" {
  description = "Where Weaviate's data lives: \"ebs\" creates and attaches the gp3 volume; \"nvme\" uses the instance-store NVMe (i4i, c6id, ...) and creates no volume."
  type        = string
  default     = "ebs"
  validation {
    condition     = contains(["ebs", "nvme"], var.data_disk)
    error_message = "data_disk must be ebs or nvme"
  }
}
