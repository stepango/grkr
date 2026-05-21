import { execFileSync } from "child_process";
import { Ok, Error } from "../../gleam.mjs";

/**
 * FFI for executing gh CLI commands for GitHub Projects V2 GraphQL and item-list.
 * Mirrors patterns from supervisor/exec.mjs and issue_provider/linear_http.mjs.
 * Used by github_picker/client.gleam for thin shell delegation.
 */

export function runGhApiGraphql(query) {
  try {
    // Note: query may contain newlines; passed as single arg value after =
    const args = ["api", "graphql", "-f", "query=" + query];
    const output = execFileSync("gh", args, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
      maxBuffer: 10 * 1024 * 1024,
      timeout: 30_000,
    });
    return new Ok(output);
  } catch (err) {
    const stderr = err?.stderr ? String(err.stderr) : "";
    const message = (stderr.trim() || err.message || "gh api graphql failed")
      .replaceAll('"', "'"); // safe for shell emit
    return new Error(message);
  }
}

export function runGhProjectItemList(projectNumber, owner) {
  try {
    const args = [
      "project",
      "item-list",
      String(projectNumber),
      "--owner",
      owner,
      "--limit",
      "1000",
      "--format",
      "json",
    ];
    const output = execFileSync("gh", args, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
      maxBuffer: 10 * 1024 * 1024,
      timeout: 30_000,
    });
    return new Ok(output);
  } catch (err) {
    const stderr = err?.stderr ? String(err.stderr) : "";
    const message = (stderr.trim() || err.message || "gh project item-list failed")
      .replaceAll('"', "'");
    return new Error(message);
  }
}
