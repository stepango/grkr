import { execFileSync } from "child_process";
import { mkdirSync, existsSync, readFileSync, writeFileSync } from "fs";
import { dirname } from "path";
import { toList, Ok, Error } from "../../gleam.mjs";

export function get_env(name) {
  return process.env[name] || "";
}

export function mkdir_p(path) {
  try {
    mkdirSync(path, { recursive: true });
    return true;
  } catch (_error) {
    return false;
  }
}

export function path_exists(path) {
  try {
    return existsSync(path);
  } catch (_error) {
    return false;
  }
}

function run_git(args, input, cwd) {
  try {
    const stdout = execFileSync("git", args.toArray(), {
      cwd: cwd,
      input: input || "",
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return { exit_code: 0, stdout: stdout, stderr: "" };
  } catch (error) {
    return {
      exit_code: error.status || 1,
      stdout: error.stdout || "",
      stderr: error.stderr || error.message || "",
    };
  }
}

export function git_exec(args, input) {
  // For prepare, base_ref, cleanup etc - host repo context (cwd or GRKR_ROOT)
  const cwd = process.cwd();
  return run_git(args, input, cwd);
}

export function git_exec_in_context(args, input) {
  // For collect/stage/git during impl - respect CURRENT_ISSUE_WORKTREE if set
  const cwd = get_env("CURRENT_ISSUE_WORKTREE") || process.cwd();
  return run_git(args, input, cwd);
}

export function argv() {
  return toList(process.argv.slice(2));
}

// --- decision gate FFI (added for t_cbc53ef5) ---

export function read_file(path) {
  try {
    if (!existsSync(path)) {
      return new Error("file not found: " + path);
    }
    const content = readFileSync(path, "utf-8");
    return new Ok(content);
  } catch (error) {
    return new Error(String(error.message || error));
  }
}

export function update_progress_for_decision(progress_file, decision) {
  try {
    let progress = {};
    if (existsSync(progress_file)) {
      const content = readFileSync(progress_file, "utf-8");
      progress = JSON.parse(content || "{}");
    }
    const now = new Date().toISOString();
    progress.decision = decision;
    progress.updated_at = now;
    if (!progress.stages) {
      progress.stages = {};
    }
    if (!progress.stages.implement_or_refuse) {
      progress.stages.implement_or_refuse = {};
    }
    progress.stages.implement_or_refuse.status = "done";
    if (decision === "proceed") {
      progress.status = "implementing";
    } else {
      progress.decision = "refuse";
    }
    const dir = dirname(progress_file);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(progress_file, JSON.stringify(progress, null, 2) + "\n", { encoding: "utf-8" });
    return new Ok(undefined);
  } catch (error) {
    console.error("update_progress_for_decision failed:", error);
    return new Error(String(error.message || error));
  }
}

// --- general executable for gh, codex, timeout etc (for handle_comment port per t_05a253d1) ---
// mirrors supervisor/exec.mjs + resolve_pr pattern; supports Gleam List via toArray
export function executable(command, args, input) {
  try {
    const options = {
      input: input || undefined,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    };
    if (process.env.GRKR_ROOT) {
      options.cwd = process.env.GRKR_ROOT;
    }
    const argsArray = args && typeof args.toArray === "function" ? args.toArray() : (Array.isArray(args) ? args : []);
    const stdout = execFileSync(command, argsArray, options);
    return { exit_code: 0, stdout: stdout, stderr: "" };
  } catch (error) {
    return {
      exit_code: error.status || 1,
      stdout: error.stdout || "",
      stderr: error.stderr || error.message || "",
    };
  }
}
