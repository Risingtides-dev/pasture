# stitchpad — TASKS

> Working backlog. Priority order top-down.

## ✅ Done (this session, 2026-06-14)
- [x] **Rename chatroom → stitchpad everywhere.** `sp_` prefix, `STITCHPAD_HOME`,
      `stitchpad.md`, `.stitchpad/`, `stitchpad-git`, `sgit`. `stitchpad-tui`
      symlink created. Zero old-name leftovers (grep-verified).
- [x] **Fix watcher bug.** Root cause was NOT stdin consumption (handoff was
      wrong) — it was an unbraced `$old` next to a Unicode `→` in a log line;
      bash bound the multibyte char into the var name. Fixed by bracing + ASCII
      arrows. Verified: watcher fires clean, no unbound-var.
- [x] **THE WAKE = tmux** (this replaced the MCP-pull / TTY-injection ideas).
      `tool/adapters/tmux.sh` does `tmux send-keys` into the teammate's pane.
      Universal across runtimes, supported, safe. Verified end-to-end: a real
      `@mention` lands a nudge in a real pane.
- [x] **MCP server** (`tool/mcp/server.mjs`): join/say/read/who. `join`
      auto-detects the caller's `$TMUX_PANE` → plug-and-play registration. No
      `wait_for_mention` (wake is push, not poll). Verified over stdio JSON-RPC.
- [x] **TUI verified** + fixed a roster-fence parse leak. Live redraw, colors,
      roster rail, q-to-quit all work.
- [x] **README + install.sh.** Install symlinks survive (symlink-safe lib
      resolution + STITCHPAD_HOME auto-derive). Full E2E passes with no env set.

## 🔁 Later / optional
- [ ] **Auto-join on MCP session load.** Right now the agent must *call* `join`
      once. Consider a session-start nudge (system-prompt note, or an MCP
      "initialized" hook) so registration is truly zero-touch.
- [ ] **Stale-pane GC.** If a registered tmux pane dies, the watcher should
      notice (tmux has-session / list-panes) and mark the teammate offline
      instead of failing send-keys.
- [ ] **`notify` adapter rename.** `claude.sh` is really the notify-only
      fallback; consider renaming the file to `notify.sh` (kept as claude.sh for
      now for back-compat).
- [ ] **Migrate Librarian onto it** — chief + larry on a real
      `.stitchpad/stitchpad.md`. Optional; Librarian is fine without it.

---
### Test pattern that worked
init in `/tmp/...`; make a real tmux session+pane; join that pane on the tmux
adapter; `stitchpad start`; `stitchpad say` a mention; `tmux capture-pane` to
assert the nudge landed. For the MCP, drive `server.mjs` with JSON-RPC over stdin.

### Verified working (don't re-litigate)
init · join · say · read · roster/who · mention detection (start-of-line @name,
ignores casual) · tmux wake (send-keys into pane) · MCP join/say/read/who with
pane auto-detect · isolated-git blame trail · TUI live render · install symlinks.
