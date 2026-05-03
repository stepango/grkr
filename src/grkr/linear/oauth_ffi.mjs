import { Ok, Error } from "../../gleam.mjs";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { homedir } from "os";
import https from "https";

/**
 * Execute OAuth token exchange request
 * @param {string} clientId - OAuth client ID
 * @param {string} clientSecret - OAuth client secret
 * @param {string} code - Authorization code
 * @param {string} redirectUri - Redirect URI
 * @returns {Promise<Array<"Ok" | "Error", TokenExchangeResponse | TokenExchangeError>>}
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
        try {
          if (res.statusCode === 200) {
            const jsonData = JSON.parse(data);
            const response = {
              access_token: jsonData.access_token,
              token_type: jsonData.token_type || "bearer",
              expires_in: jsonData.expires_in ? new Ok(jsonData.expires_in) : new Error(null),
              refresh_token: jsonData.refresh_token ? new Ok(jsonData.refresh_token) : new Error(null),
              scope: jsonData.scope ? new Ok(jsonData.scope) : new Error(null),
            };
            resolve(new Ok(response));
          } else {
            const error = mapOAuthError(res.statusCode, data);
            resolve(new Error(error));
          }
        } catch (e) {
          resolve(new Error(["InvalidResponse", []]));
        }
      });
    });

    req.on("error", (err) => {
      resolve(new Error(["NetworkError", [err.message]]));
    });

    req.write(postData);
    req.end();
  });
}

/**
 * Map OAuth error response to TokenExchangeError
 * @param {number} statusCode - HTTP status code
 * @param {string} body - Response body
 * @returns {TokenExchangeError}
 */
function mapOAuthError(statusCode, body) {
  try {
    const jsonData = JSON.parse(body);
    const error = jsonData.error || "";

    switch (error) {
      case "invalid_request":
        return ["InvalidRequest", []];
      case "invalid_client":
        return ["InvalidClient", []];
      case "invalid_grant":
        return ["InvalidGrant", []];
      case "unauthorized_client":
        return ["UnauthorizedClient", []];
      case "unsupported_grant_type":
        return ["UnsupportedGrantType", []];
      case "access_denied":
        return ["AccessDenied", []];
      case "invalid_scope":
        return ["InvalidScope", []];
      default:
        return ["ServerError", [error]];
    }
  } catch (e) {
    return ["ServerError", [`HTTP ${statusCode}`]];
  }
}

/**
 * Write token to file
 * @param {string} path - File path (may contain ~)
 * @param {string} token - Access token
 * @returns {Array<"Ok" | "Error", Nil | TokenStoreError>}
 */
export function write_token_file(path, token) {
  try {
    const expandedPath = path.replace(/^~/, homedir());
    writeFileSync(expandedPath, token, "utf-8");
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
    const expandedPath = path.replace(/^~/, homedir());

    if (!existsSync(expandedPath)) {
      return new Error(["TokenStoreNotFound", []]);
    }

    const content = readFileSync(expandedPath, "utf-8").trim();

    if (!content) {
      return new Error(["TokenStoreInvalid", []]);
    }

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
    const expandedPath = path.replace(/^~/, homedir());
    return existsSync(expandedPath);
  } catch (error) {
    return false;
  }
}

/**
 * Parse token exchange response from JSON string
 * @param {string} json - JSON string
 * @returns {Array<"Ok" | "Error", TokenExchangeResponse | TokenExchangeError>}
 */
export function parse_token_response_json(json) {
  try {
    const jsonData = JSON.parse(json);

    if (!jsonData.access_token || !jsonData.token_type) {
      return new Error(["InvalidResponse", []]);
    }

    const response = {
      access_token: jsonData.access_token,
      token_type: jsonData.token_type,
      expires_in: jsonData.expires_in ? new Ok(jsonData.expires_in) : new Error(null),
      refresh_token: jsonData.refresh_token ? new Ok(jsonData.refresh_token) : new Error(null),
      scope: jsonData.scope ? new Ok(jsonData.scope) : new Error(null),
    };

    return new Ok(response);
  } catch (e) {
    return new Error(["InvalidResponse", []]);
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
