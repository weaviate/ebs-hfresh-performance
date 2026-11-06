#!/bin/bash
# Confirm the dataset downloaded fully and record its shape, metric and vector norms.
set -euo pipefail
source /etc/ebs-blog.env
[ -f "$DATASET" ] || { echo "dataset not present yet: $(cat /datasets/download.out 2>/dev/null | tail -2)"; exit 1; }
ls -l "$DATASET"; cat /datasets/download.log 2>/dev/null || true
python3 - "$DATASET" <<'EOF' | tee /results/dataset-info.txt
import sys, h5py, numpy as np
f = h5py.File(sys.argv[1], "r")
print("attrs:", dict(f.attrs))
for k in f.keys():
    print(k, f[k].shape, f[k].dtype)
t = f["train"][:2000]
n = np.linalg.norm(t, axis=1)
print("train norms: min %.4f mean %.4f max %.4f (1.0 = unit vectors, cosine == dot)" % (n.min(), n.mean(), n.max()))
EOF
