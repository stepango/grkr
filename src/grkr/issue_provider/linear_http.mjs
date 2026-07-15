import { execFileSync } from "child_process";
import { Ok, Error } from "../../gleam.mjs";

export function postGraphqlSync(endpoint, authorizationHeader, query) {
  const script = String.raw`
const https = require("https");
const endpoint = process.argv[1];
const authorizationHeader = process.env.GRKR_LINEAR_GRAPHQL_AUTHORIZATION || "";
let payload = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => { payload += chunk; });
process.stdin.on("end", () => {
  const url = new URL(endpoint);
  const body = JSON.stringify({ query: payload });
  const request = https.request({
    method: "POST",
    hostname: url.hostname,
    path: url.pathname + url.search,
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body),
      "Authorization": authorizationHeader,
      "User-Agent": "grkr-linear-provider"
    }
  }, response => {
    let out = "";
    response.setEncoding("utf8");
    response.on("data", chunk => { out += chunk; });
    response.on("end", () => {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        process.stdout.write(out);
      } else {
        process.stderr.write("Linear GraphQL HTTP " + response.statusCode);
        process.exit(1);
      }
    });
  });
  request.on("error", error => {
    process.stderr.write("Linear GraphQL request failed: " + error.message);
    process.exit(1);
  });
  request.write(body);
  request.end();
});
`;

  try {
    const output = execFileSync(process.execPath, ["-e", script, endpoint], {
      input: query,
      encoding: "utf8",
      env: {
        ...process.env,
        GRKR_LINEAR_GRAPHQL_AUTHORIZATION: authorizationHeader,
      },
      maxBuffer: 10 * 1024 * 1024,
      timeout: 30_000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    return new Ok(output);
  } catch (err) {
    const stderr = err?.stderr ? String(err.stderr) : "";
    const message = stderr.trim() || err.message || "Linear GraphQL request failed";
    return new Error(message.replaceAll(authorizationHeader, "[REDACTED]"));
  }
}

export function postGraphqlWithVariablesSync(endpoint, authorizationHeader, query, variablesJsonString) {
  const script = String.raw`
const https = require("https");
const endpoint = process.argv[1];
const variablesJson = process.argv[2] || "{}";
const authorizationHeader = process.env.GRKR_LINEAR_GRAPHQL_AUTHORIZATION || "";
let payload = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => { payload += chunk; });
process.stdin.on("end", () => {
  const url = new URL(endpoint);
  let vars = {};
  try { vars = JSON.parse(variablesJson); } catch (e) { vars = {}; }
  const body = JSON.stringify({ query: payload, variables: vars });
  const request = https.request({
    method: "POST",
    hostname: url.hostname,
    path: url.pathname + url.search,
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body),
      "Authorization": authorizationHeader,
      "User-Agent": "grkr-linear-provider"
    }
  }, response => {
    let out = "";
    response.setEncoding("utf8");
    response.on("data", chunk => { out += chunk; });
    response.on("end", () => {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        process.stdout.write(out);
      } else {
        process.stderr.write("Linear GraphQL HTTP " + response.statusCode);
        process.exit(1);
      }
    });
  });
  request.on("error", error => {
    process.stderr.write("Linear GraphQL request failed: " + error.message);
    process.exit(1);
  });
  request.write(body);
  request.end();
});
`;

  const vars = variablesJsonString || "{}";
  try {
    const output = execFileSync(process.execPath, ["-e", script, endpoint, vars], {
      input: query,
      encoding: "utf8",
      env: {
        ...process.env,
        GRKR_LINEAR_GRAPHQL_AUTHORIZATION: authorizationHeader,
      },
      maxBuffer: 10 * 1024 * 1024,
      timeout: 30_000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    return new Ok(output);
  } catch (err) {
    const stderr = err?.stderr ? String(err.stderr) : "";
    const message = stderr.trim() || err.message || "Linear GraphQL request failed";
    return new Error(message.replaceAll(authorizationHeader, "[REDACTED]"));
  }
}
