import { execFileSync } from "child_process";

export function executable(command, args, input) {
  try {
    const stdout = execFileSync(command, args.toArray(), {
      input,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return { exit_code: 0, stdout: stdout, stderr: "" };
  } catch (error) {
    return {
      exit_code: error.status || 1,
      stdout: error.stdout || "",
      stderr: error.stderr || error.message
    };
  }
}
