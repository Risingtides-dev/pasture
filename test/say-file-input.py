#!/usr/bin/env python3
"""Exercise the real CLI in a disposable, offline pad; never starts a watcher."""
import argparse
import base64
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell", default="/bin/bash")
    args = parser.parse_args()
    cli = Path(__file__).resolve().parents[1] / "tool/bin/stitchpad"
    with tempfile.TemporaryDirectory(prefix="pasture-say-file-") as folder:
        root = Path(folder)
        pad = root / ".stitchpad"
        pad.mkdir()
        document = pad / "stitchpad.md"
        document.write_text("# Fixture\n\n```roster\nalice | codex | pull | -\n```\n")
        (root / "home").mkdir()
        env = {
            "PATH": os.defpath + ":/opt/homebrew/bin",
            "HOME": str(root / "home"),
            "STITCHPAD_NAME": "alice",
            "STITCHPAD_HEARTBEAT_AUTOSTART": "0",
            "STITCHPAD_PAD_DIR": str(root),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        git = ["git", f"--git-dir={pad / 'stitchpad-git'}", f"--work-tree={pad}"]
        for command in (["init", "-q"], ["config", "user.name", "fixture"],
                        ["config", "user.email", "fixture@example.invalid"]):
            subprocess.run(git + command, check=True, env=env, capture_output=True)

        def invoke(*arguments, stdin=None, pass_fds=()):
            return subprocess.run([args.shell, str(cli), "say", *arguments],
                                  input=stdin, text=True, capture_output=True,
                                  cwd=root, env=env, timeout=10, pass_fds=pass_fds)

        passed = 0

        def accepted(label, expected, *arguments, stdin=None, pass_fds=()):
            nonlocal passed
            before = document.read_bytes()
            result = invoke(*arguments, stdin=stdin, pass_fds=pass_fds)
            assert result.returncode == 0, (label, result.stderr)
            after = document.read_bytes()
            assert after.startswith(before), label
            assert after[len(before):].endswith(("\n\n" + expected + "\n").encode()), (label, after[len(before):])
            committed = subprocess.check_output(git + ["show", "HEAD:stitchpad.md"], env=env)
            assert committed == after, label + ": pad commit differs"
            passed += 1
            print("PASS:", label)

        def rejected(label, *arguments, stdin=None):
            nonlocal passed
            before = document.read_bytes()
            commit = subprocess.check_output(git + ["rev-parse", "HEAD"], env=env)
            result = invoke(*arguments, stdin=stdin)
            assert result.returncode != 0, (label, result.stdout)
            assert document.read_bytes() == before, label + ": changed pad"
            assert subprocess.check_output(git + ["rev-parse", "HEAD"], env=env) == commit, label + ": committed"
            passed += 1
            print("PASS:", label)

        accepted("existing trailing arguments", "ordinary message", "ordinary", "message")
        payload = "Keep `--ignored` and $(touch NEVER_EXECUTE) literally.\n\nUnicode: 界"
        body = root / "body with spaces.txt"
        body.write_text(payload)
        accepted("file preserves literal multiline text", payload, "--file", str(body))
        accepted("stdin preserves literal multiline text", payload, "--file", "-", stdin=payload)
        reader, writer = os.pipe()
        try:
            os.write(writer, payload.encode())
            os.close(writer)
            accepted("readable descriptor input", payload, "--file", f"/dev/fd/{reader}", pass_fds=(reader,))
        finally:
            os.close(reader)
        assert not (root / "NEVER_EXECUTE").exists()
        rejected("mixed input is refused", "--file", str(body), "discarded")
        rejected("duplicate file input is refused", "--file", str(body), "--file", str(body))
        rejected("missing path is refused", "--file")
        rejected("nonexistent path is refused", "--file", str(root / "missing"))
        rejected("directory read failure is refused", "--file", str(root))
        empty = root / "empty.txt"
        empty.touch()
        rejected("empty file is refused", "--file", str(empty))
        rejected("empty stdin is refused", "--file", "-", stdin="")
        accepted("option terminator keeps literal flag text", "--file literal", "--", "--file", "literal")

        # Exercise existing image validation/upload composition using a fake curl.
        # All ordinary cases above need no network command at all.
        fake_bin = root / "bin"
        fake_bin.mkdir()
        fake_curl = fake_bin / "curl"
        fake_curl.write_text(
            "#!/bin/sh\n"
            'printf "upload\\n" >> "$FIXTURE_UPLOAD_LOG"\n'
            "printf '%s\\n' '{\"url\":\"https://relay.test/tiny.png\"}'\n"
        )
        fake_curl.chmod(0o755)
        upload_log = root / "uploads.log"
        env.update(PATH=str(fake_bin) + ":" + env["PATH"],
                   FIXTURE_UPLOAD_LOG=str(upload_log),
                   STITCHPAD_RELAY="https://relay.test", STITCHPAD_TOKEN="fixture")
        image = root / "tiny.png"
        image.write_bytes(base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p94AAAAASUVORK5CYII="
        ))
        image_md = "![tiny.png](https://relay.test/tiny.png)"
        accepted("file before image", payload + "\n\n" + image_md,
                 "--file", str(body), "--image", str(image))
        accepted("image before file", payload + "\n\n" + image_md,
                 "--image", str(image), "--file", str(body))
        accepted("existing image-only message", image_md, "--image", str(image))
        uploads = upload_log.read_bytes()
        rejected("read failure prevents image upload", "--image", str(image), "--file", str(root))
        rejected("duplicate image is refused", "--image", str(image), "--image", str(image))
        assert upload_log.read_bytes() == uploads
        print(f"{passed} CLI scenarios passed with {args.shell}; no network or runtime lifecycle actions")


if __name__ == "__main__":
    main()
