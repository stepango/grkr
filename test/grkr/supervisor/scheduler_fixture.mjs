import fs from "fs";
import os from "os";
import path from "path";
import { execFileSync } from "child_process";

/** Temp workspace + mock grkr for spawn_issue_execution tests. */
export function prepare_issue_spawn_fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "grkr-scheduler-test-"));
  const runnerLog = path.join(root, "runner.log");
  fs.writeFileSync(runnerLog, "");

  const grkrPath = path.join(root, "grkr");
  const script = `#!/bin/bash\nprintf '%s\\n' "$*" >> "${runnerLog}"\nsleep 1\nexit 0\n`;
  fs.writeFileSync(grkrPath, script, { mode: 0o755 });

  return [root, runnerLog];
}

export function write_bin_grkr_mock(root, runnerLog) {
  const binDir = path.join(root, "bin");
  fs.mkdirSync(binDir, { recursive: true });
  const grkrPath = path.join(binDir, "grkr");
  const script = `#!/bin/bash\nprintf '%s\\n' "$*" >> "${runnerLog}"\nsleep 1\nexit 0\n`;
  fs.writeFileSync(grkrPath, script, { mode: 0o755 });
  try {
    fs.unlinkSync(path.join(root, "grkr"));
  } catch (_) {
    // root grkr absent — exercise bin/grkr fallback
  }
}

export function read_runner_log(logPath) {
  try {
    return fs.readFileSync(logPath, "utf8");
  } catch (_) {
    return "";
  }
}

export function cleanup_fixture(root) {
  try {
    fs.rmSync(root, { recursive: true, force: true });
  } catch (_) {
    // best-effort
  }
}

export function pause_for_spawn() {
  try {
    execFileSync("sleep", ["0.5"], { stdio: "ignore" });
  } catch (_) {
    // ignore
  }
}