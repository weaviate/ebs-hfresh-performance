# Results summary

Generated 2026-09-09 13:15 UTC

## Volume calibration (fio, before each phase)

| phase | 4k randread IOPS | mean read latency (us) | 1M seqread MiB/s |
|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 3049 | 82749 | 129 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 81389 | 3110 | 2100 |
| instance-store NVMe (i4i) | 349620 | 730 | 2817 |

## Query sweep (searchProbe x clients)

| phase | clients | searchProbe | QPS | recall@10 | mean ms | p99 ms |
|---|---|---|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 8 | 32 | 10.2 | 0.496 | 784 | 1284 |
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 8 | 64 | 9.8 | 0.512 | 817 | 1426 |
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 8 | 128 | 9.1 | 0.533 | 871 | 1710 |
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 8 | 256 | 8.5 | 0.549 | 933 | 1992 |
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 32 | 64 | 9.8 | 0.512 | 3248 | 5708 |
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 32 | 256 | 8.1 | 0.549 | 3927 | 8726 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 8 | 32 | 279.5 | 0.496 | 28 | 45 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 8 | 64 | 209.5 | 0.512 | 38 | 60 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 8 | 128 | 153.6 | 0.533 | 52 | 87 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 8 | 256 | 115.4 | 0.549 | 69 | 127 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 32 | 32 | 275.5 | 0.496 | 115 | 176 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 32 | 64 | 260.1 | 0.512 | 122 | 204 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 32 | 128 | 238.4 | 0.533 | 132 | 235 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 32 | 256 | 215.9 | 0.549 | 145 | 269 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 128 | 32 | 270.5 | 0.496 | 465 | 764 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 128 | 64 | 253.2 | 0.512 | 494 | 808 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 128 | 128 | 219.7 | 0.533 | 570 | 985 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 128 | 256 | 178.0 | 0.549 | 704 | 1236 |
| instance-store NVMe (i4i) | 8 | 32 | 436.0 | 0.493 | 18 | 32 |
| instance-store NVMe (i4i) | 8 | 64 | 361.8 | 0.510 | 22 | 34 |
| instance-store NVMe (i4i) | 8 | 128 | 273.3 | 0.533 | 29 | 44 |
| instance-store NVMe (i4i) | 8 | 256 | 195.4 | 0.549 | 41 | 60 |
| instance-store NVMe (i4i) | 32 | 32 | 637.5 | 0.493 | 50 | 77 |
| instance-store NVMe (i4i) | 32 | 64 | 560.8 | 0.510 | 56 | 91 |
| instance-store NVMe (i4i) | 32 | 128 | 425.4 | 0.533 | 75 | 120 |
| instance-store NVMe (i4i) | 32 | 256 | 300.9 | 0.549 | 105 | 163 |
| instance-store NVMe (i4i) | 128 | 32 | 641.4 | 0.493 | 197 | 297 |
| instance-store NVMe (i4i) | 128 | 64 | 560.3 | 0.510 | 224 | 354 |
| instance-store NVMe (i4i) | 128 | 128 | 414.2 | 0.533 | 304 | 493 |
| instance-store NVMe (i4i) | 128 | 256 | 276.0 | 0.549 | 456 | 743 |

## rescoreLimit sensitivity (searchProbe 64, 32 clients)

| phase | rescoreLimit | QPS | recall@10 | p99 ms |
|---|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 100 | 29.3 | 0.501 | 2599 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 100 | 761.0 | 0.501 | 77 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 350 | 257.6 | 0.512 | 205 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 1000 | 96.9 | 0.514 | 468 |
| instance-store NVMe (i4i) | 100 | 1036.6 | 0.499 | 53 |
| instance-store NVMe (i4i) | 350 | 558.8 | 0.510 | 92 |
| instance-store NVMe (i4i) | 1000 | 242.0 | 0.512 | 192 |

**Headline (32 clients, searchProbe 64):** 9.8 QPS at baseline vs 260.1 QPS at max = **26.6x** on the same node, data and 8 GiB cap.

## Disk telemetry during sweeps (iostat, per phase)

| phase | mean read IOPS | peak read IOPS | mean rMiB/s | mean read size KiB | mean r_await ms | mean util % |
|---|---|---|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 3074 | 10836 | 27.7 | 9.2 | 63.94 | 100 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 76806 | 108199 | 700.6 | 9.3 | 1.79 | 100 |
| instance-store NVMe (i4i) | 144190 | 211656 | 1349.2 | 9.6 | 0.26 | 99 |

## Container memory (cgroup memory.current)

| phase | peak GiB | peak anon GiB | peak file (page cache) GiB |
|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 8.00 | 1.47 | 7.02 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 8.00 | 3.13 | 6.87 |
| instance-store NVMe (i4i) | 8.00 | 3.03 | 6.88 |
