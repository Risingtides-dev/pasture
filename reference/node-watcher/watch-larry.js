#!/usr/bin/env node

/**
 * watch-larry.js — Agent-to-agent bridge for Librarian
 *
 * Watches SCRATCHPAD.md for @larry mentions from Claude Code.
 * When detected, spawns a Pi session with the larry extension,
 * which forces the agent to read the scratchpad, execute, and
 * write results back.
 *
 * Flow:
 *   Claude Code writes @larry task → fswatch detects →
 *   Pi session spawns (larry extension loads) →
 *   Larry reads scratchpad, executes, writes results →
 *   Claude Code sees results on next file read
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");

const LIBRARIAN_ROOT = path.join(require("os").homedir(), "librarian");
const SCRATCHPAD = path.join(LIBRARIAN_ROOT, "SCRATCHPAD.md");
const LOG_FILE = path.join(LIBRARIAN_ROOT, "scripts", "larry-watcher.log");
const BATCH_WINDOW_MS = 3000; // Wait for user to finish typing
const QUIET_PERIOD_MS = 2000; // Quiet before processing
const PI_TIMEOUT_MS = 300_000; // 5 min max per Pi session

let lastHash = null;
let lastSelfWrittenHash = null;
let batchTimer = null;
let quietTimer = null;
let processing = false;
let piProcess = null;

// ── Logging ──────────────────────────────────────────────────
function log(msg) {
  const ts = new Date().toISOString().replace("T", " ").slice(0, 19);
  const line = `[${ts}] ${msg}`;
  console.log(line);
  try {
    fs.appendFileSync(LOG_FILE, line + "\n");
  } catch {}
}

// ── Hash ────────────────────────────────────────────────────
function hashFile() {
  try {
    return crypto
      .createHash("md5")
      .update(fs.readFileSync(SCRATCHPAD, "utf8"))
      .digest("hex");
  } catch {
    return null;
  }
}

// ── Check for @larry in latest content ──────────────────────
function hasLarryRequest() {
  try {
    const content = fs.readFileSync(SCRATCHPAD, "utf8");
    const lines = content.split("\n");

    // Look for @larry in the most recent section (after last ## header)
    let lastHeader = -1;
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].startsWith("## ")) {
        lastHeader = i;
        break;
      }
    }

    const recentContent =
      lastHeader >= 0 ? lines.slice(lastHeader).join("\n") : content;

    // Check if @larry appears in recent content (case-insensitive)
    if (!recentContent.toLowerCase().includes("@larry")) return null;

    // Extract the task text — everything after the @larry mention
    const larryIdx = recentContent.toLowerCase().indexOf("@larry");
    const taskText = recentContent.slice(larryIdx).trim();

    return taskText || null;
  } catch {
    return null;
  }
}

// ── Kill Pi child ──────────────────────────────────────────
function killPi() {
  if (piProcess && !piProcess.killed) {
    try {
      piProcess.kill("SIGTERM");
    } catch {}
    setTimeout(() => {
      if (piProcess && !piProcess.killed) {
        try {
          piProcess.kill("SIGKILL");
        } catch {}
      }
    }, 5000);
    piProcess = null;
  }
}

// ── Spawn Pi session ────────────────────────────────────────
function spawnLarry(taskText) {
  return new Promise((resolve) => {
    const prompt = [
      `You are Larry, a SwiftUI frontend specialist.`,
      `Read SCRATCHPAD.md for your full context and operating rules.`,
      `The Claude Code agent just tagged you with this task:\n`,
      taskText,
      `\nExecute the task. Write your results back to SCRATCHPAD.md when done.`,
    ].join("\n");

    log(`🔧 Spawning Pi (larry extension) — ${taskText.length} chars task`);
    log(`   Preview: ${taskText.slice(0, 100).replace(/\n/g, " ")}...`);

    const proc = spawn(
      "/opt/homebrew/bin/pi",
      [
        "-p",                    // non-interactive: process and exit
        "--name", "Larry · librarian",
        prompt,
      ],
      {
        stdio: ["ignore", "pipe", "pipe"],
        env: {
          ...process.env,
          // Extension auto-discovered from ~/.pi/agent/extensions/larry/
        },
        cwd: LIBRARIAN_ROOT,
      }
    );

    piProcess = proc;
    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (d) => {
      stdout += d.toString();
      // Log progress in real-time
      const lines = d.toString().split("\n").filter((l) => l.trim());
      for (const line of lines.slice(-3)) {
        log(`   pi> ${line.slice(0, 120)}`);
      }
    });

    proc.stderr.on("data", (d) => {
      stderr += d.toString();
    });

    const timeout = setTimeout(() => {
      log("⏰ Pi session timed out (5 min)");
      killPi();
      processing = false;
      resolve(null);
    }, PI_TIMEOUT_MS);

    proc.on("close", (code) => {
      clearTimeout(timeout);
      piProcess = null;

      if (code === 0) {
        log(`✅ Pi session completed (exit 0)`);
        resolve(stdout.trim());
      } else {
        log(`❌ Pi exited ${code}`);
        if (stderr) log(`   stderr: ${stderr.slice(0, 200)}`);
        resolve(null);
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timeout);
      piProcess = null;
      log(`❌ Pi spawn error: ${err.message}`);
      resolve(null);
    });
  });
}

// ── Process @larry request ──────────────────────────────────
async function processRequest(taskText) {
  if (processing) {
    log("⏭️  Already processing a request");
    return;
  }
  processing = true;

  log(`📨 @larry request detected: ${taskText.length} chars`);

  try {
    const result = await spawnLarry(taskText);
    if (result) {
      log("📝 Task completed, results written to SCRATCHPAD.md");
    }
  } catch (err) {
    log(`❌ Error: ${err.message}`);
  } finally {
    processing = false;
  }
}

// ── Handle file change (batched) ───────────────────────────
function handleChange() {
  clearTimeout(quietTimer);
  clearTimeout(batchTimer);
  batchTimer = setTimeout(() => {
    clearTimeout(quietTimer);
    quietTimer = setTimeout(() => processBatch(), QUIET_PERIOD_MS);
  }, BATCH_WINDOW_MS);
}

async function processBatch() {
  if (processing) {
    log("⏭️  Skipping batch (processing)");
    return;
  }

  const currentHash = hashFile();
  if (!currentHash) return;
  if (currentHash === lastSelfWrittenHash) {
    lastHash = currentHash;
    return;
  }
  if (currentHash === lastHash) return;
  lastHash = currentHash;

  // Let file settle
  await new Promise((r) => setTimeout(r, 500));

  const taskText = hasLarryRequest();
  if (!taskText) {
    log("📄 Scratchpad changed but no @larry found");
    return;
  }

  await processRequest(taskText);
}

// ── Main ───────────────────────────────────────────────────
async function main() {
  log("🔧 Larry Watcher — Agent-to-Agent bridge for Librarian");
  log(`📄 Watching: ${SCRATCHPAD}`);
  log(`⏱️  Batch: ${BATCH_WINDOW_MS}ms | Quiet: ${QUIET_PERIOD_MS}ms`);
  log(`🔧 Backend: pi --path-to-librarian (larry extension)`);
  log(`⏰ Timeout: ${PI_TIMEOUT_MS / 1000}s`);

  lastHash = hashFile();
  log("⏳ Ready — waiting for @larry tasks from Claude Code");

  // Use fswatch (available on macOS via Homebrew)
  const watcher = spawn("/opt/homebrew/bin/fswatch", [
    "--latency",
    "0.5",
    "--event",
    "Updated",
    SCRATCHPAD,
  ]);

  watcher.stdout.on("data", () => handleChange());
  watcher.stderr.on("data", (d) =>
    log(`⚠️  fswatch: ${d.toString().trim()}`)
  );
  watcher.on("close", (code) => {
    log(`⚠️  fswatch exited (${code}). Restarting in 2s...`);
    setTimeout(main, 2000);
  });

  let done = false;
  const shutdown = () => {
    if (done) return;
    done = true;
    log("👋 Shutting down");
    clearTimeout(batchTimer);
    clearTimeout(quietTimer);
    killPi();
    watcher.kill();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  log(`❌ Fatal: ${err.message}`);
  process.exit(1);
});
