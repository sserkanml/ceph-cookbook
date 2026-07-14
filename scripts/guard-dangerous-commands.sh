#!/bin/bash
# Blocks or warns before Claude runs destructive/irreversible Ceph commands.
# Receives hook input as JSON on stdin.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Patterns considered destructive/irreversible
DANGEROUS_PATTERNS=(
  "ceph osd pool delete"
  "ceph osd out"
  "ceph osd purge"
  "ceph osd rm"
  "rados rm"
  "rados purge"
  "radosgw-admin period commit"
  "radosgw-admin realm delete"
  "radosgw-admin zone delete"
  "ceph pg force-recovery"
  "ceph pg repair"
  "--yes-i-really-mean-it"
  "--yes-i-really-really-mean-it"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qF "$pattern"; then
    echo "{\"decision\": \"block\", \"reason\": \"This command ($pattern) is destructive or hard to reverse. Confirm with the user explicitly before running it, and explain the blast radius first.\"}"
    exit 0
  fi
done

# No dangerous pattern matched — allow
echo "{\"decision\": \"approve\"}"
EOF