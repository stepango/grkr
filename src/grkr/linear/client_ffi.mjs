import { Ok, Error, toList, Empty } from "../../gleam.mjs";
import { to_list as dictToList } from "../../../gleam_stdlib/gleam/dict.mjs";
import {
  GraphQLResponse,
  LinearArchiveResult,
  LinearComment,
  LinearIssue,
  LinearProject,
  LinearTeam,
  LinearUser,
} from "./types.mjs";

const LINEAR_API_URL = "https://api.linear.app/graphql";

/**
 * Convert a Gleam Dict(String, String) (or plain object, or null) into a
 * plain JS object suitable for JSON.stringify in GraphQL variables.
 * Defensive: never throws on bad input; empty -> {}.
 */
export function variablesToObject(variables) {
  if (variables == null) return {};
  // Plain JS object (not a Gleam Dict which has "size" and "root")
  if (
    typeof variables === "object" &&
    variables !== null &&
    !("root" in variables) &&
    !("size" in variables) &&
    typeof variables.toArray !== "function"
  ) {
    return { ...variables };
  }
  // Legacy objects that expose toArray (e.g. old lists or custom)
  if (typeof variables.toArray === "function") {
    try {
      return Object.fromEntries(variables.toArray());
    } catch (_) {
      return {};
    }
  }
  // Gleam Dict via stdlib to_list -> walk Gleam List of [k, v]
  try {
    const list = dictToList(variables);
    const out = {};
    let cur = list;
    while (cur && !(cur instanceof Empty)) {
      const pair = cur.head;
      if (pair != null) {
        const k = pair[0];
        const v = pair[1];
        if (k != null) out[k] = v;
      }
      cur = cur.tail;
    }
    return out;
  } catch (_) {
    if (typeof variables === "object" && variables !== null) {
      try {
        return { ...variables };
      } catch (_) {
        return {};
      }
    }
    return {};
  }
}

export function variablesToJson(variables) {
  return JSON.stringify(variablesToObject(variables));
}

export async function execute_graphql_request(token, query) {
  try {
    const response = await fetch(LINEAR_API_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        query: query.query,
        variables: variablesToObject(query.variables),
      }),
    });

    if (!response.ok) {
      return new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const data = await response.json();

    if (data.errors) {
      const messages = data.errors.map(e => e.message);
      return new Ok(new GraphQLResponse(
        new Error(messages.join(", ")),
        toList(messages),
      ));
    }

    return new Ok(new GraphQLResponse(new Ok(data.data), toList([])));
  } catch (error) {
    return new Error("Request failed: " + error.message);
  }
}

export function parse_viewer_json(data) {
  try {
    const viewer = data?.viewer;
    if (!viewer) {
      return new Error("Missing viewer data");
    }

    return new Ok(new LinearUser(
      viewer.id || "",
      viewer.name || "",
      viewer.email || "",
    ));
  } catch (error) {
    return new Error("Failed to parse viewer: " + error.message);
  }
}

export function parse_projects_json(data) {
  try {
    const projects = data?.projects?.nodes;
    if (!Array.isArray(projects)) {
      return new Error("Missing or invalid projects data");
    }

    const parsed = projects.map(p => new LinearProject(
      p.id || "",
      p.name || "",
      p.url || "",
    ));

    return new Ok(toList(parsed));
  } catch (error) {
    return new Error("Failed to parse projects: " + error.message);
  }
}

export function parse_teams_json(data) {
  try {
    const teams = data?.teams?.nodes;
    if (!Array.isArray(teams)) {
      return new Error("Missing or invalid teams data");
    }

    const parsed = teams.map(t => new LinearTeam(
      t.id || "",
      t.name || "",
      t.key || "",
    ));

    return new Ok(toList(parsed));
  } catch (error) {
    return new Error("Failed to parse teams: " + error.message);
  }
}

function issueFromObject(issue) {
  return new LinearIssue(
    issue?.id || "",
    issue?.title || "",
    issue?.description || "",
    issue?.url || "",
    issue?.state?.id || "",
  );
}

function payloadFailed(payload, operation) {
  if (payload?.success === false) {
    return new Error(`${operation} returned success=false`);
  }

  return null;
}

export function parse_issue_json(data) {
  try {
    const issue = data?.issue;
    if (!issue) {
      return new Error("Missing issue data");
    }

    return new Ok(issueFromObject(issue));
  } catch (error) {
    return new Error("Failed to parse issue: " + error.message);
  }
}

export function parse_created_issue_json(data) {
  try {
    const payload = data?.issueCreate;
    const failed = payloadFailed(payload, "Issue create");
    if (failed) {
      return failed;
    }

    const issue = payload?.issue;
    if (!issue) {
      return new Error("Missing created issue data");
    }

    return new Ok(issueFromObject(issue));
  } catch (error) {
    return new Error("Failed to parse created issue: " + error.message);
  }
}

export function parse_comment_json(data) {
  try {
    const payload = data?.commentCreate;
    const failed = payloadFailed(payload, "Comment create");
    if (failed) {
      return failed;
    }

    const comment = payload?.comment;
    if (!comment) {
      return new Error("Missing created comment data");
    }

    return new Ok(new LinearComment(
      comment.id || "",
      comment.body || "",
    ));
  } catch (error) {
    return new Error("Failed to parse created comment: " + error.message);
  }
}

export function parse_archive_json(data) {
  try {
    const archive = data?.issueArchive;
    if (!archive) {
      return new Error("Missing issue archive data");
    }
    const failed = payloadFailed(archive, "Issue archive");
    if (failed) {
      return failed;
    }

    return new Ok(new LinearArchiveResult(Boolean(archive.success)));
  } catch (error) {
    return new Error("Failed to parse issue archive: " + error.message);
  }
}
