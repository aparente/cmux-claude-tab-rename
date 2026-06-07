# cmux-claude-tab-rename

Two things, both about making multi-session [Claude Code](https://claude.com/claude-code) inside [cmux](https://github.com/manaflow-ai/cmux) survivable:

1. **Auto-rename cmux tabs to your Claude session name.** Updates on start, resume, picker selection, and `/rename` mid-session. Restores to the prior title on exit.
2. **Rewrite cmux's notification panel to show the tab name, not just the workspace.** When you have 8 Claude sessions in one workspace, you can tell *which one* is waiting for input.

If you run 5+ Claude sessions across cmux tabs and lose track of which is which, this fixes that.

> **You might also like:** [`claude-code-sessions`](https://github.com/aparente/claude-code-sessions) — checkpoint your live Claude sessions every 5 min and restore them across crashes / cmux restarts. Separate problem, works alongside this one.

---

## Tab renaming

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

## Notification rewrite

cmux's notification panel renders every Claude "needs input" event with the same title (`Claude Code`) and the *workspace* name as the footer. If you have 8 Claude sessions in one workspace, that's 8 identical-looking notifications.

This kit installs a cmux notification hook that rewrites `notification.title` to the firing tab's name, so the panel becomes useful again:

| Before | After |
|---|---|
| **Claude Code** <br/> Claude is waiting for your input <br/> Biobrain | **Mom Kim Tasks** <br/> Claude is waiting for your input <br/> Biobrain |

The cmux side of this works via `~/.config/cmux/cmux.json` → `notifications.hooks`. cmux pipes each notification's policy JSON through your script and renders whatever you return — including content changes (`title`, `subtitle`, `body`), not just effects toggles.

The hook can't ask cmux for the tab title at notification time (that deadlocks the cmux socket cmux is currently using to deliver the notification), so the tab-rename script doubles as a cache writer — every time it renames a tab, it updates `~/Library/Caches/cmux-tab-rename/tab-titles.json` with the new `surfaceId → title` entry. The notification hook reads that cache. (Per-user `~/Library/Caches/` rather than `/tmp/` so the cache is mode-protected and free from TOCTOU pre-create issues on shared machines.)

---

## Requirements

- **macOS** with [cmux](https://github.com/manaflow-ai/cmux) installed
- **zsh** as your shell (the helpers use zsh-only syntax)
- **Claude Code CLI** on `$PATH`
- **python3** on `$PATH` (used for JSON parsing and transcript reads)

---

## Install via Claude Code

Open a Claude Code session and paste:

> Please install the cmux Claude-session tab-rename + notification kit from this repo: https://github.com/aparente/cmux-claude-tab-rename. Read the README, then install all five files: the zsh wrapper (appended to `~/.zshrc`), the two Claude Code hook scripts (`~/.claude/scripts/`), the Claude Code settings entries (`~/.claude/settings.json`), and the cmux notification hook block (`~/.config/cmux/cmux.json`). Use absolute paths derived from my home directory (no `~`). Be idempotent — if `claude()` is already a shell function in my `~/.zshrc`, replace just that block. After install, run `cmux reload-config`, source `~/.zshrc`, and confirm the four shell functions are defined.

Claude will fetch raw files from the repo, install them, register the hook, and verify.

---

## Install manually

### 1. Shell helpers (drop into `~/.zshrc`)

```bash
curl -fsSL https://raw.githubusercontent.com/aparente/cmux-claude-tab-rename/main/cmux-claude-tab-rename.zsh >> ~/.zshrc
```

If you already had a `claude()` function defined elsewhere in `~/.zshrc`, **replace** it — zsh keeps whichever was defined last. The function in this file does naming AND tab rename; it's a superset.

### 2. Claude Code hook scripts

```bash
mkdir -p ~/.claude/scripts
curl -fsSL https://raw.githubusercontent.com/aparente/cmux-claude-tab-rename/main/cmux-rename-on-session.sh \
  -o ~/.claude/scripts/cmux-rename-on-session.sh
curl -fsSL https://raw.githubusercontent.com/aparente/cmux-claude-tab-rename/main/cmux-notification-add-tab-name.sh \
  -o ~/.claude/scripts/cmux-notification-add-tab-name.sh
chmod +x ~/.claude/scripts/cmux-rename-on-session.sh \
         ~/.claude/scripts/cmux-notification-add-tab-name.sh
```

### 3. Register the Claude Code hooks in `~/.claude/settings.json`

Merge the `hooks.SessionStart` and `hooks.Stop` entries from [`settings-snippet.json`](./settings-snippet.json) into your `~/.claude/settings.json`. Substitute your `$USER` for `YOUR_USERNAME` — `~` is not expanded in hook commands.

### 4. Register the cmux notification hook in `~/.config/cmux/cmux.json`

Merge the `notifications.hooks` block from [`cmux-config-snippet.jsonc`](./cmux-config-snippet.jsonc) into your `~/.config/cmux/cmux.json` (a JSONC file with comments — preserve the existing `$schema` and `schemaVersion` keys). Substitute your username. Then:

```bash
cmux reload-config
```

Skip this step if you don't want the notification rewrite. The tab rename works on its own.

### 5. Activate

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
rm ~/.claude/scripts/cmux-notification-add-tab-name.sh
rm -rf ~/Library/Caches/cmux-tab-rename
# Edit ~/.zshrc: delete the helper functions and the claude() function block
# Edit ~/.claude/settings.json: remove the SessionStart and Stop entries
# Edit ~/.config/cmux/cmux.json: remove the notifications.hooks entry, then:
cmux reload-config
```

## Files

| File | Goes to | Purpose |
|---|---|---|
| [`cmux-claude-tab-rename.zsh`](./cmux-claude-tab-rename.zsh) | append to `~/.zshrc` | Shell wrapper: auto-name prompt + pre-launch rename + on-exit restore |
| [`cmux-rename-on-session.sh`](./cmux-rename-on-session.sh) | `~/.claude/scripts/` | SessionStart + Stop hook: renames tab to match session title; also writes the surface→title cache |
| [`cmux-notification-add-tab-name.sh`](./cmux-notification-add-tab-name.sh) | `~/.claude/scripts/` | cmux notification hook: reads the cache and rewrites notification.title to the firing tab's name |
| [`settings-snippet.json`](./settings-snippet.json) | merge into `~/.claude/settings.json` | Claude Code hook registration |
| [`cmux-config-snippet.jsonc`](./cmux-config-snippet.jsonc) | merge into `~/.config/cmux/cmux.json` | cmux notification hook registration |

## Status

- [x] Tab rename on session start/resume/`-n`/`--resume UUID`
- [x] Tab rename on `/rename` mid-session
- [x] Restore to prior title on session exit
- [x] Rewrite cmux's "needs input" notifications to show tab name instead of workspace name

## License

[CC0 1.0 Universal](./LICENSE) — public domain.
