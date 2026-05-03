import { execFileSync } from "child_process";

export function executable(command, args, input) {
  try {
    const options = {
      input,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    };
    if (process.env.GRKR_ROOT) {
      options.cwd = process.env.GRKR_ROOT;
    }

    const stdout = execFileSync(command, args.toArray(), options);
    return { exit_code: 0, stdout: stdout, stderr: "" };
  } catch (error) {
    return {
      exit_code: error.status || 1,
      stdout: error.stdout || "",
      stderr: error.stderr || error.message
    };
  }
}
