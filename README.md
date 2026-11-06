# HFresh on Amazon EBS gp3: a reproducible performance test

This repository holds everything needed to re-run the benchmark behind Weaviate's
blog post on serving a 10-million-vector HFresh index from 8 GiB of RAM on Amazon EBS
gp3: the Terraform rig, the orchestration scripts, the Weaviate configuration, the raw
measurements and the rendered charts.

The question the test answers: when Weaviate's HFresh index is forced to live on disk
instead of in RAM, how much does the provisioned performance of the EBS volume matter?

## Headline result

Same instance, same dataset, same 8 GiB memory cap. The only change between the two
rows is one `aws ec2 modify-volume` call.

| configuration | QPS | p99 latency | recall@10 |
|---|---|---|---|
| gp3 at 3,000 IOPS / 125 MiB/s (default) | 9.8 | 5.7 s | 0.512 |
| gp3 at 80,000 IOPS / 2,000 MiB/s | 260 | 204 ms | 0.512 |
| instance-store NVMe (i4i.8xlarge), for comparison | 561 | 91 ms | 0.512 |

Measured at 32 concurrent clients and `searchProbe` 64. Full tables are in
`results/summary.md` and `results/summary-nvme.md`.

## What the rig looks like

- One **server**: `c6in.8xlarge` (32 vCPU, instance EBS cap of 100k IOPS), Amazon Linux
  2023, Docker Compose, Weaviate 1.39.3 with `DEFAULT_VECTOR_INDEX=hfresh`, hard-capped
  with cgroup v2 at 8 GiB including page cache (`compose/`).
- One **data volume**: 400 GiB gp3, created at 80,000 IOPS and modified live between
  phases. The NVMe variant uses the instance store of an `i4i.8xlarge` instead.
- One **client**: `c7i.2xlarge` running
  [weaviate-benchmarking](https://github.com/weaviate/weaviate-benchmarking) built
  inside Docker (commit in `results/benchmarker-commit.txt`).
- **Dataset**: `sphere-10M-meta-dpr` (10M x 768-d, 31 GB HDF5, public, URL in
  `infra/variables.tf`).
- **Network**: both instances sit in a private subnet with no public IPv4 address.
  Outbound traffic (package installs, image pull, the dataset download) leaves through a
  NAT gateway; S3 traffic uses a gateway endpoint. Shell access goes through an EC2
  Instance Connect Endpoint (`scripts/aws/ssm.sh`) with a throw-away key, so there is no
  inbound path from the internet and no stored key pair. An S3 bucket ferries scripts out
  and results back.
- **Safety**: a server-side dead-man's switch (`scripts/server/deadman.sh`) stops
  Weaviate, syncs results and powers the instance off after a timer, so a dropped
  session cannot leave the rig running.

Each measurement phase: fio calibration of the volume, drop caches, pin readahead,
restart Weaviate under the cap, capture iostat / cgroup memory / Prometheus metrics on
the server, warm up, then sweep clients 8/32/128 x `searchProbe` 32/64/128/256, then
`rescoreLimit` 100/350/1000.

## Reproducing the test

Expect roughly 6 to 8 hours of wall clock and around $35 to $50 of AWS spend for the
EBS phases. The baseline phase is slow by construction (10k queries at ~9 QPS per data
point). The NAT gateway adds a few dollars: an hourly charge plus per-GB processing for
the 31 GB dataset download. The original run placed the instances in a public subnet;
the move to a private subnet changes nothing about the storage path being measured.

Prerequisites on the operator machine: Terraform >= 1.5, AWS CLI v2, `jq`, `ssh`,
Python 3 with `pip install -r scripts/analyze/requirements.txt`.

1. **Account and profile.** Use a throwaway AWS account or a sandbox you can audit
   afterwards. Configure a profile (the scripts default to `AWS_PROFILE=ebs-blog`).
   If you load short-lived keys from a file, `scripts/aws/load-keys.sh` parses the
   access-portal format into that profile and `scripts/aws/preflight.sh` fails fast
   when they expire.
2. **Pick an AZ** that offers `c6in.8xlarge`:
   ```
   aws ec2 describe-instance-type-offerings --location-type availability-zone \
     --filters Name=instance-type,Values=c6in.8xlarge --region us-east-2
   ```
   and set `availability_zone` in `infra/variables.tf` (or pass `-var`).
3. **Build the rig.**
   ```
   cd infra && terraform init && terraform apply
   scripts/aws/modify-volume.sh 80000 2000      # provider caps throughput at 1000 on create
   scripts/aws/sync-to-hosts.sh                 # ship compose/ and scripts/ to both hosts
   ```
4. **Import** (about 20 minutes plus the dataset download):
   ```
   scripts/run-import.sh
   ```
   Calibrates the volume with fio, starts Weaviate with a relaxed 32 GiB cap, imports the
   dataset, waits for compactions, stops Weaviate and snapshots the volume.
5. **Measure.** The volume starts at 80k / 2,000.
   ```
   scripts/run-phase.sh phase-2-max      headline-pread.env 80000-2000
   scripts/aws/modify-volume.sh 3000 125
   scripts/run-phase.sh phase-1-baseline headline-pread.env 3000-125
   ```
   Add `quick` as a fourth argument for a 30-second dry run. gp3 allows four
   modifications per 24 hours.
6. **Render.**
   ```
   python3 scripts/analyze/render.py    # writes results/summary.md and charts/*.png
   ```
7. **Tear down and verify nothing is left.** Detached gp3 volumes keep billing their
   provisioned IOPS.
   ```
   scripts/aws/teardown.sh
   scripts/aws/teardown-check.sh us-east-2
   ```

### NVMe variant

```
cd infra && terraform apply -var data_disk=nvme -var server_instance_type=i4i.8xlarge
scripts/aws/sync-to-hosts.sh
EBS_LABEL=nvme scripts/run-import.sh
scripts/run-phase.sh phase-4-nvme headline-pread.env nvme
python3 scripts/analyze/render.py
scripts/aws/teardown.sh
```
Instance-store data does not survive a stop, so there is no snapshot step and the
dead-man's switch erases the data when it fires.

## Two things worth knowing before you run it

**mmap caps in-flight IO at GOMAXPROCS.** With Weaviate's default
`PERSISTENCE_LSM_ACCESS_STRATEGY=mmap`, every posting or object read is a page fault
that pins an OS thread, so the volume never saw more than ~25 outstanding IOs and
plateaued at ~40k IOPS and ~82 QPS regardless of client count. Switching to `pread`
turns reads into syscalls the Go runtime can hand off: 85k IOPS, 250 in flight, 252
QPS. The `*-pread.env` files are therefore the headline configuration; the mmap sweep
is kept in `results/phase-2-max-mmap/` as the first surprise of the test.

**The benchmarker ignores `--rescoreLimit` in query-only mode**, so `sweep.sh` sets
`rq.rescoreLimit` through the schema API instead.

## Repository layout

```
compose/           docker-compose.yml plus one .env per phase (memory cap, GOMEMLIMIT, LSM strategy)
infra/             Terraform: VPC, instances, gp3 volume, Instance Connect Endpoint, results bucket
scripts/aws/       operator side: tunnel, sync, volume modification, CloudWatch export, teardown
scripts/server/    on the server: fio calibration, disk tuning, reset, capture, dead-man's switch
scripts/client/    on the client: build the benchmarker, check the dataset, import, sweep
scripts/run-*.sh   the import and phase orchestrators
scripts/analyze/   render.py: results/ -> summary tables and charts
results/           raw measurements (see below)
charts/            rendered charts for the EBS phases; charts/nvme/ for the NVMe run
```

### Results

| path | contents |
|---|---|
| `results/summary.md`, `summary-nvme.md` | rendered tables: fio calibration, query sweep, rescore sensitivity, iostat and memory |
| `results/phase-0-calibration/` | fio runs against the gp3 volume at each setting |
| `results/phase-1-baseline/` | gp3 3,000 / 125, pread, 8 GiB cap (partial: 8-client sweep complete, 32-client probe 64 and 256, rescore 100) |
| `results/phase-2-max/` | gp3 80,000 / 2,000, pread, 8 GiB cap (headline) |
| `results/phase-2-max-mmap/` | same volume with the default mmap strategy |
| `results/phase-3-control/` | empty: the 56 GiB in-RAM control phase was not run |
| `results/phase-4-nvme/` | i4i.8xlarge instance store, pread, 8 GiB cap |
| `results/import/` | import timings and the post-import disk footprint |
| `results/*.run.log`, `volume-modifications.log`, `deadman.log` | operator logs as they happened |

Inside each phase: `probe-sweep-p<clients>.json` and `rescore-r<limit>-p32.json` from the
benchmarker, `fio-*.json` and `fio-summary.txt`, `host-state.txt`, `container-limits.txt`,
`cloudwatch-ebs.json`, and `sweep/` with `iostat.json`, `cgroup-mem.csv`, `mpstat.txt`
and one Prometheus scrape per second under `metrics/`.

The volume, snapshot and instance IDs that appear in the logs belong to a sandbox account
that was emptied after the test.

## Lessons from running it

- Instance Connect tunnels drop after about an hour. Run sweeps detached on the client
  and poll for a `DONE` marker (this is what `run-phase.sh` does now); never hold a
  tunnel open across a run.
- Short-lived SSO keys expire mid-run. Call `preflight.sh` before every remote step.
- A gp3 down-modification sits in `optimizing` for an hour or more while the new limits
  are already in force. fio confirms the target before `completed`.
- Budget the baseline phase at three times the max phase, or use the `quick` mode to
  check the pipeline first.
- gp3 needs at least 160 GiB to allow 80,000 IOPS, and the instance type sets its own
  ceiling (c7i.8xlarge stops at 40k; c6in.8xlarge allows 100k).

## License

See `LICENSE`.
