# Results summary

Generated 2026-09-09 13:15 UTC

## Volume calibration (fio, before each phase)

| phase | 4k randread IOPS | mean read latency (us) | 1M seqread MiB/s |
|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 3049 | 82749 | 129 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 81389 | 3110 | 2100 |
| gp3 max, mmap (first attempt) | 81389 | 3104 | 2100 |

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
| gp3 max, mmap (first attempt) | 8 | 32 | 91.0 | 0.496 | 88 | 129 |
| gp3 max, mmap (first attempt) | 8 | 64 | 68.6 | 0.512 | 116 | 174 |
| gp3 max, mmap (first attempt) | 8 | 128 | 49.9 | 0.533 | 159 | 268 |
| gp3 max, mmap (first attempt) | 8 | 256 | 37.7 | 0.549 | 211 | 417 |
| gp3 max, mmap (first attempt) | 32 | 32 | 97.9 | 0.496 | 324 | 597 |
| gp3 max, mmap (first attempt) | 32 | 64 | 84.0 | 0.512 | 377 | 676 |
| gp3 max, mmap (first attempt) | 32 | 128 | 69.8 | 0.533 | 454 | 771 |
| gp3 max, mmap (first attempt) | 32 | 256 | 57.1 | 0.549 | 553 | 945 |
| gp3 max, mmap (first attempt) | 128 | 32 | 97.6 | 0.496 | 1287 | 2194 |
| gp3 max, mmap (first attempt) | 128 | 64 | 82.5 | 0.512 | 1518 | 2686 |
| gp3 max, mmap (first attempt) | 128 | 128 | 65.9 | 0.533 | 1903 | 3199 |
| gp3 max, mmap (first attempt) | 128 | 256 | 47.1 | 0.549 | 2660 | 4559 |

## rescoreLimit sensitivity (searchProbe 64, 32 clients)

| phase | rescoreLimit | QPS | recall@10 | p99 ms |
|---|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 100 | 29.3 | 0.501 | 2599 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 100 | 761.0 | 0.501 | 77 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 350 | 257.6 | 0.512 | 205 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 1000 | 96.9 | 0.514 | 468 |

**Headline (32 clients, searchProbe 64):** 9.8 QPS at baseline vs 260.1 QPS at max = **26.6x** on the same node, data and 8 GiB cap.

## Disk telemetry during sweeps (iostat, per phase)

| phase | mean read IOPS | peak read IOPS | mean rMiB/s | mean read size KiB | mean r_await ms | mean util % |
|---|---|---|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 3074 | 10836 | 27.7 | 9.2 | 63.94 | 100 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 76806 | 108199 | 700.6 | 9.3 | 1.79 | 100 |
| gp3 max, mmap (first attempt) | 38860 | 45618 | 491.9 | 12.9 | 0.60 | 100 |

## Container memory (cgroup memory.current)

| phase | peak GiB | peak anon GiB | peak file (page cache) GiB |
|---|---|---|---|
| gp3 baseline (3,000 IOPS / 125 MiB/s) | 8.00 | 1.47 | 7.02 |
| gp3 max (80,000 IOPS / 2,000 MiB/s) | 8.00 | 3.13 | 6.87 |
| gp3 max, mmap (first attempt) | 8.00 | 2.78 | 6.85 |
