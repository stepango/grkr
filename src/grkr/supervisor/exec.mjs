import { execFileSync } from "child_process";

export function executable(command, args, input) {
  try {
    const inputStr =
      input == null || typeof input !== "string" ? undefined : input;
    const options = {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    };
    if (inputStr !== undefined) {
      options.input = inputStr;
    }
    if (process.env.GRKR_ROOT) {
      options.cwd = process.env.GRKR_ROOT;
    }
    const argsArray = args && typeof args.toArray === "function" ? args.toArray() : (Array.isArray(args) ? args : []);
    const stdout = execFileSync(command, argsArray, options);
    return { exit_code: 0, stdout: stdout, stderr: "" };
  } catch (error) {
    return {
      exit_code: error.status || 1,
      stdout: error.stdout || "",
      stderr: error.stderr || error.message || "",
    };
  }
}
