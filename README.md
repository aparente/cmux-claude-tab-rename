# cmux-claude-tab-rename

Auto-rename [cmux](https://github.com/manaflow-ai/cmux) tabs to match your [Claude Code](https://claude.com/claude-code) session name. Tab updates on start, resume, picker selection, and mid-session `/rename`. Restores to the prior title when the session exits.

If you run 5+ Claude sessions across cmux tabs and lose track of which is which, this fixes that.

> **You might also like:** [`claude-code-sessions`](https://github.com/aparente/claude-code-sessions) — checkpoint your live Claude sessions every 5 min and restore them across crashes / cmux restarts. Separate problem, works alongside this one.

---

## What does what

| You run | Tab becomes | At session exit |
|---|---|---|
| `claude` (bare) | prompts you for a name → renames to that | restores prior title |
| `claude -n "Foo"` | `Foo` | restores prior title |
| `claude --resume <UUID>` | the session's saved title | restores prior title |
| `claude --resume <searchterm>` | renamed once you pick from the picker | restores prior title |
| `claude -c` / `--continue` | resolved session's title | restores prior title |
| `/rename NewName` mid-session | tab updates to `NewName` on the next response | restores prior title on exit |
| `claude attach 12345678` (and other subcommands) | unchanged | unchanged |

Outside cmux (plain Terminal, IDE without cmux), all the rename code paths no-op silently.

---

## Requirements

- **macOS** with [cmux](https://github.com/manaflow-ai/cmux) installed
- **zsh** as your shell (the helpers use zsh-only syntax)
- **Claude Code CLI** on `$PATH`
- **python3** on `$PATH` (used for JSON parsing and transcript reads)

---

## Install via Claude Code

Open a Claude Code session and paste:

> Please install the cmux Claude-session tab-rename workflow from this repo: https://github.com/aparente/cmux-claude-tab-rename. Read the README, then install the three files (shell helpers, hook script, settings entry). Use absolute paths derived from my home directory (no ~). Be idempotent — if `claude()` is already a shell function in my `~/.zshrc`, replace just that block; don't duplicate. Verify the install by sourcing `~/.zshrc` and confirming the four functions (`claude`, `_claude_rename_cmux_tab`, `_claude_current_tab_title`, `_claude_rename_from_args`) are defined.

Claude will fetch raw files from the repo, install them, register the hook, and verify.

---

## Install manually

### 1. Shell helpers (drop into `~/.zshrc`)

```bash
curl -fsSL https://raw.githubusercontent.com/aparente/cmux-claude-tab-rename/main/cmux-claude-tab-rename.zsh >> ~/.zshrc
```

If you already had a `claude()` function defined elsewhere in `~/.zshrc`, **replace** it — zsh keeps whichever was defined last. The function in this file does naming AND tab rename; it's a superset.

### 2. SessionStart/Stop hook script

```bash
mkdir -p ~/.claude/scripts
curl -fsSL https://raw.githubusercontent.com/aparente/cmux-claude-tab-rename/main/cmux-rename-on-session.sh \
  -o ~/.claude/scripts/cmux-rename-on-session.sh
chmod +x ~/.claude/scripts/cmux-rename-on-session.sh
```

### 3. Register the hooks in `~/.claude/settings.json`

Merge the `hooks.SessionStart` and `hooks.Stop` entries from [`settings-snippet.json`](./settings-snippet.json) into your `~/.claude/settings.json`. Substitute your `$USER` for `YOUR_USERNAME` — `~` is not expanded in hook commands.

### 4. Activate

```bash
source ~/.zshrc
```

New Claude sessions pick up the hooks automatically — no Claude Code restart needed.

---

## Verify

```bash
# All four helpers loaded
whence -w claude _claude_rename_cmux_tab _claude_current_tab_title _claude_rename_from_args

# Hook script in place
ls -l ~/.claude/scripts/cmux-rename-on-session.sh

# Hooks registered
python3 -c "import json; print(list(json.load(open('$HOME/.claude/settings.json'))['hooks'].keys()))"
```

Then test: in a cmux tab named `Terminal`, run `claude -n "rename-test"`. The tab should immediately become `rename-test`. Exit the session and it should snap back to `Terminal`. After resuming a session, try `/rename "another-name"` mid-conversation — on the next assistant response, the tab updates.

---

## How it works

Two complementary mechanisms.

**Pre-launch** (the zsh helpers): Before `claude` runs, the shell function inspects the args. If it sees `-n "Name"`, that's the new tab title. If it sees `--resume <UUID>`, it reads the title out of the transcript JSONL at `~/.claude/projects/*/UUID.jsonl`. It also captures the current tab title so it can be restored on exit.

**During-session** (SessionStart + Stop hooks): For entry paths the shell can't resolve (picker `--resume <searchterm>`, `-c`, IDE launches), Claude Code fires the SessionStart hook *after* it knows which session is running. The Stop hook re-checks after every assistant turn, so a `/rename` mid-session updates the tab on the next response. Both call the same script. Idempotent with the pre-launch rename.

cmux exposes `$CMUX_SURFACE_ID` and `$CMUX_WORKSPACE_ID` in every tab, so a process can identify and rename its own tab via `cmux rename-tab --surface "$CMUX_SURFACE_ID" "<title>"`.

The hook runs **synchronously**. Backgrounding it (with `&`) lets Claude Code's hook runner reap the script's process group when it exits, killing the cmux subprocess mid-write to the cmux socket — manifests as "Broken pipe (errno 32)". Synchronous cost is ~50–340ms per turn depending on transcript size, well under the 5s hook timeout.

---

## Customize

- **Don't want the per-turn rename refresh?** Drop just the `Stop` block from `settings.json`. You lose mid-session `/rename` auto-update; everything else still works.
- **Don't want the tab to restore on session exit?** Remove the two `[[ -n "$_prev_title" ]] && _claude_rename_cmux_tab "$_prev_title"` lines from the shell function.
- **Don't want the bare-launch naming prompt?** Replace the `printf "Session name..."` / `read -r name` block with `command claude "$@"`. Keeps all the rename behavior, drops the prompt.

## Uninstall

```bash
rm ~/.claude/scripts/cmux-rename-on-session.sh
# Edit ~/.zshrc: delete the helper functions and the claude() function block
# Edit ~/.claude/settings.json: remove the SessionStart and Stop entries
```

## Files

| File | Goes to | Purpose |
|---|---|---|
| [`cmux-claude-tab-rename.zsh`](./cmux-claude-tab-rename.zsh) | append to `~/.zshrc` | Shell wrapper: auto-name prompt + pre-launch rename + on-exit restore |
| [`cmux-rename-on-session.sh`](./cmux-rename-on-session.sh) | `~/.claude/scripts/` | SessionStart + Stop hook script |
| [`settings-snippet.json`](./settings-snippet.json) | merge into `~/.claude/settings.json` | Hook registration |

## Status

- [x] Tab rename on session start/resume/`-n`/`--resume UUID` — working
- [x] Tab rename on `/rename` mid-session — working
- [x] Restore to prior title on session exit — working
- [ ] Rewrite cmux's "needs input" notifications to show tab name instead of workspace name — see [Issue #1](https://github.com/aparente/cmux-claude-tab-rename/issues/1)

## License

[CC0 1.0 Universal](./LICENSE) — public domain.
