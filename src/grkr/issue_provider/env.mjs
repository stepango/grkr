/**
 * FFI module for environment variable access
 */

/**
 * Get an environment variable value
 * @param {string} name - The environment variable name
 * @returns {string} The environment variable value or empty string if not set
 */
export function getEnv(name) {
  return process.env[name] || "";
}

/**
 * Get an environment variable value as a Result type
 * @param {string} name - The environment variable name
 * @returns {Array} Ok(value) or Error(Nil)
 */
export function getEnvResult(name) {
  const value = process.env[name];
  if (value && value.trim() !== "") {
    return [true, value];
  }
  return [false, null];
}

/**
 * Check if an environment variable is set
 * @param {string} name - The environment variable name
 * @returns {boolean} True if the variable is set and non-empty
 */
export function hasEnv(name) {
  const value = process.env[name];
  return !!(value && value.trim() !== "");
}
