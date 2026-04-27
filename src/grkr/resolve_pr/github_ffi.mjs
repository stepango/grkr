import { Ok, Error, toList } from "../../gleam.mjs";
import { PullRequest } from "./types.mjs";

export function parse_pr_json(output) {
  try {
    const data = JSON.parse(output);
    const authorLogin = data.author?.login || "unknown";
    const mergeStatus = data.mergeStateStatus || "";
    const conflicted =
      mergeStatus === "DIRTY" || data.mergeable === "CONFLICTING";
    const mergeable = data.mergeable === true || data.mergeable === "MERGEABLE";

    return new Ok(
      new PullRequest(
        data.number || 0,
        data.title || "",
        authorLogin,
        data.headRefName || "",
        data.headRefOid || "",
        data.baseRefName || "",
        mergeable,
        conflicted,
        Boolean(data.isCrossRepository),
      )
    );
  } catch (error) {
    return new Error("Failed to parse PR JSON: " + error.message);
  }
}

export function parse_pr_list_json(output) {
  try {
    const data = JSON.parse(output);
    if (!Array.isArray(data)) {
      return new Error("Expected array of PRs");
    }

    const prs = data.map(pr => {
      const authorLogin = pr.author?.login || "unknown";
      const mergeStatus = pr.mergeStateStatus || "";
      const conflicted =
        mergeStatus === "DIRTY" || pr.mergeable === "CONFLICTING";
      const mergeable = pr.mergeable === true || pr.mergeable === "MERGEABLE";

      return new PullRequest(
        pr.number || 0,
        pr.title || "",
        authorLogin,
        pr.headRefName || "",
        pr.headRefOid || "",
        pr.baseRefName || "",
        mergeable,
        conflicted,
        Boolean(pr.isCrossRepository),
      );
    });

    return new Ok(toList(prs));
  } catch (error) {
    return new Error("Failed to parse PR list JSON: " + error.message);
  }
}
