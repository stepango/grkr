/**
 * FFI module for environment variable access (GitHub picker)
 */

export function getEnv(name) {
  return process.env[name] || "";
}

export function getEnvResult(name) {
  const value = process.env[name];
  if (value && value.trim() !== "") {
    return [true, value];
  }
  return [false, null];
}

export function hasEnv(name) {
  const value = process.env[name];
  return !!(value && value.trim() !== "");
}
