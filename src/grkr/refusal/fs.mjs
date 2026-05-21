import { writeFileSync, readFileSync, existsSync, mkdirSync } from "fs";
import { dirname } from "path";

/**
 * FFI file helpers for refusal module (write refusal.md, update progress.json)
 * Modeled after resolve_pr/fs.mjs and supervisor/fs.mjs
 */

export function write_file(path, content) {
  try {
    const dir = dirname(path);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(path, content, { encoding: "utf-8" });
    return ["Ok", undefined];
  } catch (error) {
    return ["Error", String(error.message || error)];
  }
}

export function update_progress_for_refusal(progress_file, reason_class, comment_id) {
  try {
    let progress = {};
    if (existsSync(progress_file)) {
      const content = readFileSync(progress_file, "utf-8");
      progress = JSON.parse(content || "{}");
    }
    const now = new Date().toISOString();
    progress.status = "refused";
    progress.decision = "refuse";
    progress.updated_at = now;
    if (!progress.stages) {
      progress.stages = {};
    }
    if (!progress.stages.implement_or_refuse) {
      progress.stages.implement_or_refuse = {};
    }
    progress.stages.implement_or_refuse.status = "done";
    progress.stages.implement_or_refuse.reason_class = reason_class;
    if (comment_id && comment_id.trim() !== "") {
      const num = parseInt(comment_id, 10);
      progress.stages.implement_or_refuse.comment_id = isNaN(num) ? comment_id : num;
    } else {
      delete progress.stages.implement_or_refuse.comment_id;
    }
    if (!progress.stages.test) {
      progress.stages.test = {};
    }
    progress.stages.test.status = "skipped";
    const dir = dirname(progress_file);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(progress_file, JSON.stringify(progress, null, 2) + "\n", { encoding: "utf-8" });
    return ["Ok", undefined];
  } catch (error) {
    console.error("update_progress_for_refusal failed:", error);
    return ["Error", String(error.message || error)];
  }
}

export function exists_file(path) {
  try {
    return existsSync(path);
  } catch (_) {
    return false;
  }
}
