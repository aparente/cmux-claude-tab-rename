#!/bin/bash
# Claude Code hook — rename the current cmux tab to the session's custom title.
#
# Registered in ~/.claude/settings.json under both SessionStart and Stop:
#   SessionStart : catches picker resume / -c / IDE launches that the .zshrc
#                  claude() shell function can't resolve pre-launch.
#   Stop         : catches /name renames the user issues mid-session — the
#                  hook re-reads the latest customTitle after each turn.
#
# Idempotent: re-renaming to the same title is a no-op as far as the user
# sees. Safe to run alongside the shell-function rename.
#
# Performance: runs synchronously because Claude Code's hook runner cleans
# up the script's process group on exit — backgrounding the cmux call lets
# the parent's exit kill the cmux subprocess mid-write to the cmux socket
# (manifests as "Broken pipe, errno 32"). Synchronous cost: ~50-340ms
# depending on transcript size. Hook timeout is 5s in settings.json which
# is plenty of headroom.

# Skip if not inside a cmux surface (e.g., launched from VS Code, plain Terminal).
[ -n "$CMUX_SURFACE_ID" ] || exit 0

PAYLOAD=$(cat)

TRANSCRIPT=$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("transcript_path",""))
except Exception: print("")' 2>/dev/null)

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Extract the latest custom-title from the transcript JSONL.
TITLE=$(python3 -c '
import json, sys
t = ""
try:
    for L in open(sys.argv[1]):
        try:
            d = json.loads(L)
            if d.get("type") == "custom-title" and d.get("customTitle"):
                t = d["customTitle"]
        except Exception:
            pass
except Exception:
    pass
print(t)
' "$TRANSCRIPT" 2>/dev/null)

[ -n "$TITLE" ] || exit 0

# Synchronous: the cmux socket write must complete before this script exits,
# or the process-group cleanup will kill it mid-write.
cmux rename-tab --surface "$CMUX_SURFACE_ID" "$TITLE" >/dev/null 2>&1

# Update the surface→title cache so the cmux notification hook
# (cmux-notification-add-tab-name.sh) can look up tab titles without calling
# back into cmux (which would deadlock when invoked from inside cmux's own
# notification pipeline).
python3 - "$CMUX_SURFACE_ID" "$TITLE" <<'PY' >/dev/null 2>&1
import json, os, sys, tempfile
cache = '/tmp/cmux-tab-titles.json'
sid, title = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(cache))
except Exception:
    data = {}
data[sid] = title
fd, tmp = tempfile.mkstemp(dir='/tmp', prefix='cmux-titles.', suffix='.json')
os.write(fd, json.dumps(data).encode())
os.close(fd)
os.rename(tmp, cache)
PY

exit 0
