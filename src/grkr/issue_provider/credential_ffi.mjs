import { readFileSync, existsSync } from "fs";
import { homedir } from "os";

/**
 * Read a file, expanding ~ to home directory
 * @param {string} path - File path (may contain ~)
 * @returns {Array<"Ok" | "Error", string | Object>}
 */
export function readFile(path) {
  try {
    const expandedPath = path.replace(/^~/, homedir());

    if (!existsSync(expandedPath)) {
      return ["Error", ["CredentialFileNotFound", path]];
    }

    const content = readFileSync(expandedPath, "utf-8");
    return ["Ok", content];
  } catch (error) {
    return ["Error", ["CredentialFileNotReadable", path]];
  }
}

/**
 * Get environment variable
 * @param {string} name - Environment variable name
 * @param {string} defaultValue - Default value if not set
 * @returns {string}
 */
export function getEnv(name, defaultValue) {
  const value = process.env[name];
  return value !== undefined && value !== "" ? value : defaultValue;
}
