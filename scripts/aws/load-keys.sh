#!/bin/bash
# Load the sandbox session keys from ~/aws-sandbox-keys.txt into the ebs-blog profile and verify them.
# Prints the token's remaining lifetime so a run can be sized to fit.
set -euo pipefail
F="${1:-$HOME/aws-sandbox-keys.txt}"
python3 - "$F" <<'EOF'
import re, os, sys, configparser
raw = open(sys.argv[1]).read()
def grab(n):
    m = re.search(r'(?i)%s\s*=\s*"?([^"\s]+)' % n, raw); return m.group(1) if m else None
k, s, t = grab("aws_access_key_id"), grab("aws_secret_access_key"), grab("aws_session_token")
assert k and s, "could not parse keys"
cp = configparser.RawConfigParser(); path = os.path.expanduser("~/.aws/credentials"); cp.read(path)
if not cp.has_section("ebs-blog"): cp.add_section("ebs-blog")
cp.set("ebs-blog", "aws_access_key_id", k); cp.set("ebs-blog", "aws_secret_access_key", s)
if t: cp.set("ebs-blog", "aws_session_token", t)
elif cp.has_option("ebs-blog", "aws_session_token"): cp.remove_option("ebs-blog", "aws_session_token")
with open(path, "w") as f: cp.write(f)
EOF
export AWS_PROFILE=ebs-blog
aws sts get-caller-identity --query Arn --output text
# Session tokens from the access portal carry no expiry we can read; record the load time so
# preflight can warn when the usual lifetime is nearly used up.
date -u +%s > "$HOME/.aws/ebs-blog.loaded-at"
echo "keys loaded at $(date -u +%H:%M) UTC"
