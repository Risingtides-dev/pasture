# stitchpad — TASKS

> Working backlog. Mirrors the OPEN TASKS in HANDOFF.md so a fresh session has them
> on disk (the session task-tool list doesn't survive a new session). Check items off
> here as you go. Priority order top-down.

## 🔥 Now
- [ ] **0. Re-architect: TTY/PID + MCP (THE PIVOT).** Make wake runtime-agnostic.
      Decide wake model — recommend **MCP-inbox pull** (`wait_for_mention` tool the daemon
      flips), use PID/TTY only for targeting + notifications, NOT keystroke injection.
      Stand up a minimal stitchpad MCP server: `join / say / read / who / wait_for_mention`.
      This becomes the primary agent-facing path; CLI + TUI stay human-facing.
      → Goal: any agent adds the MCP, turns it on, is in the channel. Plug-and-play.

## 🔧 Make the existing tool trustworthy
- [ ] **1. Rename chatroom → stitchpad everywhere** in `tool/`.
      `CHATROOM_HOME`→`STITCHPAD_HOME`, `channel.md`→`stitchpad.md`, `.chatroom/`→`.stitchpad/`,
      `channel-git`→`stitchpad-git`, `cr_`→`sp_`, `cr_find_channel` looks for `.stitchpad`,
      help text + init template + comments. Delete dead `bin/chatroom-tui` symlink; make
      `bin/stitchpad-tui` → tui.sh.
- [ ] **2. Fix watcher bug** (`watch.sh` ~line 56, `old�: unbound variable`).
      Cause: inner read consumes the fswatch pipe's stdin. Ensure nothing inside the
      `fswatch | while` loop reads stdin (`< /dev/null`, here-strings, or array). Re-test
      with mock adapter until push + pull both fire cleanly.

## ✨ Finish + ship
- [ ] **3. Finish/verify TUI** (`tui.sh`): live re-render on change, author colors, roster
      rail, unread-ping indicator, `q` to quit, correct parse of roster fence + message headers.
- [ ] **4. README + install script.** Pitch, design (self-describing markdown, roster-in-file,
      @mention→wake, MCP plug-and-play), quickstart, PATH install, document `reference/`.

## 🔁 Later
- [ ] **5. Migrate Librarian onto it** — chief + larry on a real `.stitchpad/stitchpad.md`.
      Optional; Librarian is fine without it.

---
### Test pattern that worked
init in `/tmp/stitchpad-test`; swap a MOCK adapter that just logs; drive with `say`;
assert on the log. Don't spawn real `pi` in smoke tests.

### Verified working (don't re-litigate)
init · join · say · roster parse-back · mention detection (start-of-line @name, BSD-awk) ·
adapter dispatch (push/pull, via mock) · isolated-git blame trail.
