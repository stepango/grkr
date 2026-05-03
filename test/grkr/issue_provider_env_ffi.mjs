import { mkdtempSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

export function installLinearSecret(content) {
  const dir = mkdtempSync(join(tmpdir(), "grkr-linear-"));
  const path = join(dir, "secret.txt");
  writeFileSync(path, content, { encoding: "utf-8" });
  process.env.LINEAR_CREDENTIALS_PATH = path;
  return undefined;
}
