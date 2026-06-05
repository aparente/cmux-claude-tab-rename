#!/bin/zsh
# cmux + Claude Code tab-rename helpers (drop into ~/.zshrc)
#
# What it does
# ------------
# 1. Wraps `claude` to prompt for a session name if you launch a bare new
#    session — so every session you start is searchable/resumable later.
# 2. Renames the current cmux tab to the session name when you start or
#    resume by UUID. Picker resumes (--resume <searchterm>) are handled by
#    the companion SessionStart hook in cmux-rename-on-session.sh.
# 3. Restores the tab to its prior title when the Claude session exits.
#
# Pass-through cases (no rename, no prompt):
#   claude agents | attach | logs | stop | mcp | plugin | plugins
#   claude config | doctor | update | install | migrate-installer
#   claude setup-token | remote-control
#
# Requirements
# ------------
# - zsh (uses [[ =~ ]], glob qualifiers (N), and `print -rl --`)
# - cmux app — sets $CMUX_SURFACE_ID and $CMUX_WORKSPACE_ID in every tab
# - Claude Code CLI on $PATH
# - python3 on $PATH (used only for transcript parsing; ~50ms when invoked)
#
# Outside cmux ($CMUX_SURFACE_ID empty), all rename code paths no-op silently
# — safe to load in environments where cmux isn't running.

# Rename the current cmux tab to the given title (no-op outside cmux).
_claude_rename_cmux_tab() {
  [[ -n "$CMUX_SURFACE_ID" && -n "$1" ]] || return 0
  cmux rename-tab --surface "$CMUX_SURFACE_ID" "$1" >/dev/null 2>&1
}

# Read the current cmux tab's title (without ✳ indicator or [selected] suffix).
# Echoes the title or nothing. Used to capture state before renaming so we
# can restore it when the claude session exits.
_claude_current_tab_title() {
  [[ -n "$CMUX_SURFACE_ID" && -n "$CMUX_WORKSPACE_ID" ]] || return 0
  cmux --id-format uuids list-pane-surfaces --workspace "$CMUX_WORKSPACE_ID" 2>/dev/null | \
    python3 -c "
import sys, re
sid = sys.argv[1]
for L in sys.stdin:
    L = L.rstrip('\n')
    s = re.sub(r'^\* ', '', L).lstrip()
    parts = s.split(None, 1)
    if len(parts) < 2 or parts[0] != sid: continue
    title = parts[1]
    title = re.sub(r'  \[selected\]\s*$', '', title)
    title = re.sub(r'^✳ ', '', title)
    print(title.strip())
    break
" "$CMUX_SURFACE_ID" 2>/dev/null
}

# Resolve a session name from claude args and rename the cmux tab to match.
# Handles `-n/--name <name>` (free) and `--resume/-r <UUID>` (reads the title
# from the transcript). Picker/search-term resumes are unknowable pre-launch
# — the companion SessionStart hook covers those cases once Claude has
# resolved which session was picked.
_claude_rename_from_args() {
  [[ -n "$CMUX_SURFACE_ID" ]] || return 0
  local prev="" a name=""
  for a in "$@"; do
    case "$prev" in
      -n|--name) name="$a"; break ;;
      -r|--resume)
        if [[ "$a" =~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' ]]; then
          local f=$(print -rl -- ~/.claude/projects/*/"$a".jsonl(N) | head -1)
          [[ -n "$f" ]] && name=$(python3 -c "
import json,sys
t=''
for L in open(sys.argv[1]):
    try:
        d=json.loads(L)
        if d.get('type')=='custom-title' and d.get('customTitle'): t=d['customTitle']
    except Exception: pass
print(t)" "$f" 2>/dev/null)
        fi
        break ;;
    esac
    prev="$a"
  done
  _claude_rename_cmux_tab "$name"
}

claude() {
  # Pass through management subcommands (not new sessions, must not be renamed)
  case "$1" in
    agents|attach|logs|stop|mcp|plugin|plugins|config|doctor|update|install|\
    migrate-installer|setup-token|remote-control)
      command claude "$@"
      return
      ;;
  esac

  # Capture the tab's current title so we can restore it on session exit.
  local _prev_title=""
  [[ -n "$CMUX_SURFACE_ID" ]] && _prev_title=$(_claude_current_tab_title)

  local rc=0
  # Pass through for resume, continue, one-shot, pipe, help, or already named.
  # In each case we still try to extract a name from the args for the rename.
  if [[ " $* " =~ " -r " ]] || [[ " $* " =~ " --resume" ]] || \
     [[ " $* " =~ " -c " ]] || [[ " $* " =~ " --help" ]] || \
     [[ " $* " =~ " -n " ]] || [[ " $* " =~ " -p " ]]; then
    _claude_rename_from_args "$@"
    command claude "$@"; rc=$?
    [[ -n "$_prev_title" ]] && _claude_rename_cmux_tab "$_prev_title"
    return $rc
  fi

  # Bare interactive launch — prompt for a name so the session is searchable.
  printf "Session name (enter to auto-name): "
  local name
  read -r name
  if [[ -n "$name" ]]; then
    _claude_rename_cmux_tab "$name"
    command claude -n "$name" "$@"; rc=$?
  else
    command claude "$@"; rc=$?
  fi
  [[ -n "$_prev_title" ]] && _claude_rename_cmux_tab "$_prev_title"
  return $rc
}
