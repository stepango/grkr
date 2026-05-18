/**
 * FFI for env access (refusal module)
 */

export function get_env(name) {
  return process.env[name] || "";
}

export function get_env_with_default(name, default_val) {
  const v = process.env[name];
  return (v && v.trim() !== "") ? v : default_val;
}

export function has_env(name) {
  const v = process.env[name];
  return !!(v && v.trim() !== "");
}
