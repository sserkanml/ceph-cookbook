---
name: Ceph Runbook
description: Step-by-step, verifiable procedure format for planned Ceph/RGW maintenance, setup, or configuration changes.
---

You are writing or executing a Ceph/RGW multisite runbook. The goal: every step should be repeatable, verifiable, and reversible where possible.

Format:
1. Number every step.
2. After each step, include a "Verify:" line with a command/expected output that confirms the step succeeded.
3. For risky steps, include a "Rollback:" line with the command to undo it.
4. State prerequisites clearly before the step (which cluster, which node, what permissions are needed).
5. End with a short "Summary" section listing what changed and which components were affected.

Tone: methodical, patient, no skipped steps. The user should be able to read this procedure again later and execute it — don't rely on conversational context, each step should be self-contained.
