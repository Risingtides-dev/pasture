# Pasture devlog

## Purpose

- Pasture provides a markdown conversation bus for coding agents. `README.md`
  owns setup and CLI usage; `tool/PRODUCT.md` owns the browser product purpose.

## Ownership

- `tool/bin/` owns the Bash CLI, shared library and watcher lifecycle.
- `tool/mcp/` owns the agent identity and messaging bridge.
- `tool/adapters/` owns runtime integration; `tool/pwa/` owns the browser client.
- `test/` owns executable regression fixtures.
- Append history to the canonical repository-root `events.md`; isolated work
  identifies its branch and location. Preserve concurrent checkout changes.

## Local Contracts

- Preserve Bash 3.2 compatibility for the shell CLI and shared library.
- `say --file <path>` and `--file -` read message text as data. Reject duplicate
  file sources, mixed file/trailing text and failed reads before posting/upload.
  Preserve existing identity, locking, image validation and mention expansion.
- File/stdin input follows the existing text-message representation: trailing
  newlines are normalized by shell command substitution; it is not a binary
  transport.
- Source delivery does not authorize installing hooks, starting watchers,
  waking real agents or sending real messages during validation.

## Work Guidance

- Use disposable pads and isolated fixture identity/configuration for CLI tests.
- Do not import unrelated fork stacks when porting a focused fix.

## Verification

- `python3 test/say-file-input.py --shell /bin/bash` exercises the actual CLI
  with a temporary offline pad and disabled heartbeat autostart.
- Also run the fixture with an available current Bash, shell syntax checks and
  `git diff --check` for CLI changes.

## Child devlog Index

- No child devlogs.
