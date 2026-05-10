import { Ok, Error } from "../../gleam.mjs";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "fs";
import { homedir } from "os";
import { dirname } from "path";
import https from "https";

/**
 * Execute OAuth token exchange request
 * @param {string} clientId - OAuth client ID
 * @param {string} clientSecret - OAuth client secret
 * @param {string} code - Authorization code
 * @param {string} redirectUri - Redirect URI
 * @returns {Promise<Array<"Ok" | "Error", { status_code: number, body: string } | string>>}
 */
export function execute_token_exchange(clientId, clientSecret, code, redirectUri) {
  return new Promise((resolve) => {
    const postData = JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      code: code,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    });

    const options = {
      hostname: "linear.app",
      port: 443,
      path: "/oauth/token",
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(postData),
      },
    };

    const req = https.request(options, (res) => {
      let data = "";

      res.on("data", (chunk) => {
        data += chunk;
      });

      res.on("end", () => {
        resolve(new Ok({
          status_code: res.statusCode || 0,
          body: data,
        }));
      });
    });

    req.on("error", (err) => {
      resolve(new Error(err.message));
    });

    req.write(postData);
    req.end();
  });
}

/**
 * Write token to file
 * @param {string} path - File path (may contain ~)
 * @param {string} token - Access token
 * @returns {Array<"Ok" | "Error", Nil | TokenStoreError>}
 */
export function write_token_file(path, token) {
  try {
    const expandedPath = expandHome(path);
    mkdirSync(dirname(expandedPath), { recursive: true, mode: 0o700 });
    writeFileSync(expandedPath, token, { encoding: "utf-8", mode: 0o600 });
    return new Ok(null);
  } catch (error) {
    return new Error(["TokenStoreNotReadable", []]);
  }
}

/**
 * Read token from file
 * @param {string} path - File path (may contain ~)
 * @returns {Array<"Ok" | "Error", String | TokenStoreError>}
 */
export function read_token_file(path) {
  try {
    const expandedPath = expandHome(path);

    if (!existsSync(expandedPath)) {
      return new Error(["TokenStoreNotFound", []]);
    }

    const content = readFileSync(expandedPath, "utf-8");
    return new Ok(content);
  } catch (error) {
    return new Error(["TokenStoreNotReadable", []]);
  }
}

/**
 * Get environment variable
 * @param {string} name - Variable name
 * @returns {string}
 */
export function get_env_var(name) {
  return process.env[name] || "";
}

/**
 * Check if file exists
 * @param {string} path - File path (may contain ~)
 * @returns {boolean}
 */
export function file_exists(path) {
  try {
    const expandedPath = expandHome(path);
    return existsSync(expandedPath);
  } catch (error) {
    return false;
  }
}

/**
 * Read a string field from a JSON object.
 * @param {string} json - JSON string
 * @param {string} field - Field name
 * @returns {Array<"Ok" | "Error", string | null>}
 */
export function parse_token_response_json(json, field) {
  try {
    const jsonData = JSON.parse(json);
    const value = jsonData[field];
    if (typeof value !== "string" || value.length === 0) {
      return new Error(null);
    }

    return new Ok(value);
  } catch (e) {
    return new Error(null);
  }
}

/**
 * Read an integer field from a JSON object.
 * @param {string} json - JSON string
 * @param {string} field - Field name
 * @returns {Array<"Ok" | "Error", number | null>}
 */
export function json_int_field(json, field) {
  try {
    const jsonData = JSON.parse(json);
    const value = jsonData[field];
    if (!Number.isInteger(value)) {
      return new Error(null);
    }

    return new Ok(value);
  } catch (e) {
    return new Error(null);
  }
}

/**
 * Convert integer to string
 * @param {number} i - Integer value
 * @returns {string}
 */
export function int_to_string(i) {
  return String(i);
}

function expandHome(path) {
  return path.replace(/^~(?=\/|$)/, homedir());
}
