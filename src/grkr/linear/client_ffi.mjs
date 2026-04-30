import { Ok, Error, toList } from "../../gleam.mjs";
import {
  GraphQLResponse,
  LinearProject,
  LinearTeam,
  LinearUser,
} from "./types.mjs";

const LINEAR_API_URL = "https://api.linear.app/graphql";

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
        variables: Object.fromEntries(query.variables.toArray()),
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
