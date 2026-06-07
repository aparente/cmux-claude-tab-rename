#!/usr/bin/env python3
"""
cmux notification hook — rewrite the notification title to the cmux tab name
so multi-Claude-session workspaces are disambiguated at a glance.

Registered in ~/.config/cmux/cmux.json under notifications.hooks. cmux pipes
the notification policy JSON in on stdin and reads the updated JSON from stdout.
See https://github.com/manaflow-ai/cmux/blob/main/docs/notifications.md

How it knows the tab title:

We CANNOT call `cmux list-pane-surfaces` from inside this hook — cmux is
holding its socket while it processes the notification, so a CLI call back
into the same socket deadlocks until the hook times out (cmux falls back to
the original notification, losing our rewrite).

Instead we read ~/Library/Caches/cmux-tab-rename/tab-titles.json, a
surfaceId→title map that the companion cmux-rename-on-session.sh writes
every time it renames a tab. That keeps the cache fresh for any Claude
session managed through this kit, without needing to query cmux at
notification time.

If a surface isn't in the cache (e.g., tab renamed via cmux UI directly,
or a process that doesn't use our rename hook), pass through with the
original notification.
"""
import json
import os
import sys


def fail_through(policy):
    """Emit the policy as-is and exit 0 so cmux uses default behavior."""
    json.dump(policy, sys.stdout)
    sys.exit(0)


CACHE = os.path.expanduser("~/Library/Caches/cmux-tab-rename/tab-titles.json")

try:
    policy = json.load(sys.stdin)
except Exception:
    sys.stdout.write("{}")
    sys.exit(0)

notif = policy.get("notification") or {}
surface_id = notif.get("surfaceId") or ""

if not surface_id:
    fail_through(policy)

try:
    cache = json.load(open(CACHE))
except Exception:
    fail_through(policy)

tab_title = cache.get(surface_id, "")
if not tab_title:
    fail_through(policy)

original_title = notif.get("title") or ""
notif["title"] = tab_title
# Preserve the agent identity (e.g., "Claude Code") as subtitle
if original_title and original_title != tab_title:
    notif["subtitle"] = original_title
policy["notification"] = notif

json.dump(policy, sys.stdout)
sys.exit(0)
