// Tiny FFI for coding_agent: arg split, grok bin default, XAI key load.
// Keep ≤30 LOC. Match bin/lib/issue_shared_coding_agent.sh parity.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { toList } from "../gleam.mjs";

/** Best-effort shell-like word split (no quote parsing). Returns Gleam List. */
export function split_args(s) {
  if (!s || typeof s !== "string") return toList([]);
  const parts = s.trim().split(/\s+/).filter(Boolean);
  return toList(parts);
}

/** GROK_BIN, else ~/.grok/bin/grok if executable, else "grok". */
export function default_grok_bin() {
  const fromEnv = process.env.GROK_BIN;
  if (fromEnv && String(fromEnv).trim()) return String(fromEnv).trim();
  const candidate = path.join(os.homedir(), ".grok", "bin", "grok");
  try {
    fs.accessSync(candidate, fs.constants.X_OK);
    return candidate;
  } catch {
    return "grok";
  }
}

/** If XAI_API_KEY unset, best-effort load from ~/.hermes/.env (shell parity). */
export function ensure_xai_api_key() {
  if (process.env.XAI_API_KEY) return;
  const envPath = path.join(os.homedir(), ".hermes", ".env");
  try {
    const text = fs.readFileSync(envPath, "utf8");
    const line = text.split(/\r?\n/).find((l) => /^XAI_API_KEY=/.test(l));
    if (!line) return;
    let val = line.slice("XAI_API_KEY=".length).replace(/\r$/, "");
    if (
      val.length >= 2 &&
      ((val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'")))
    ) {
      val = val.slice(1, -1);
    }
    if (val) process.env.XAI_API_KEY = val;
  } catch {
    // best-effort
  }
}
