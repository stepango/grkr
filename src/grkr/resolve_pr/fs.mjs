import { writeFileSync } from "fs";

export function write_file(path, content) {
  try {
    writeFileSync(path, content, { encoding: "utf-8" });
    return ["Ok", undefined];
  } catch (error) {
    return ["Error", error.message];
  }
}
