#!/bin/bash
# Watches Ceph cluster health and only reports when the state changes.

STATE_FILE="/tmp/.ceph-health-watch-state"
INTERVAL=30

touch "$STATE_FILE"

while true; do
  CURRENT=$(ceph health 2>/dev/null)
  PREVIOUS=$(cat "$STATE_FILE" 2>/dev/null)

  if [ "$CURRENT" != "$PREVIOUS" ] && [ -n "$CURRENT" ]; then
    echo "[$(date '+%H:%M:%S')] Ceph health changed: $PREVIOUS -> $CURRENT"

    if [ "$CURRENT" != "HEALTH_OK" ]; then
      ceph health detail 2>/dev/null | head -20
    fi

    echo "$CURRENT" > "$STATE_FILE"
  fi

  sleep "$INTERVAL"
done
