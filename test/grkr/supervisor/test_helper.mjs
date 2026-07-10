export function set_env(name, value) {
  if (value === "") {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
