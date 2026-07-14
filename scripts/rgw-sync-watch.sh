#!/bin/bash
# Watches RGW multisite sync status and only reports when it changes
# (e.g. transitions between caught up, behind, or failed).

STATE_FILE="/tmp/.ceph-rgw-sync-watch-state"
INTERVAL=60

touch "$STATE_FILE"

while true; do
  CURRENT=$(radosgw-admin sync status 2>/dev/null | grep -E "failed|behind|caught up" | sort)
  PREVIOUS=$(cat "$STATE_FILE" 2>/dev/null)

  if [ "$CURRENT" != "$PREVIOUS" ] && [ -n "$CURRENT" ]; then
    echo "[$(date '+%H:%M:%S')] RGW sync status changed:"
    echo "$CURRENT"

    if echo "$CURRENT" | grep -qi "failed"; then
      echo "-- Full sync status for context --"
      radosgw-admin sync status 2>/dev/null | head -30
    fi

    echo "$CURRENT" > "$STATE_FILE"
  fi

  sleep "$INTERVAL"
done
