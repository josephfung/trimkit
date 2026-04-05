---
name: sysops
description: Invoke the sysops subagent for VPS maintenance. Use when the user runs /sysops with an optional argument like "status", "update Pulse", or "update my servers".
---

# Sysops

Immediately delegate to the `sysops` subagent using the Agent tool.

Pass the user's argument directly as the prompt. If no argument was given, default to a status check across all deployments.

Examples:
- `/sysops` → prompt: "Check the status of all my servers"
- `/sysops status` → prompt: "Check the status of all my servers"
- `/sysops update Pulse` → prompt: "Update Pulse"
- `/sysops update my servers` → prompt: "Update all my servers"

Do not add any preamble or explanation — just invoke the subagent immediately.
