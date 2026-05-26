/// Task log types (sharding support for codex implementation.log > MAX_FILE_LINES)
/// GitHub-only v2. Extracted from monolithic task_log.gleam per AGENTS.md + t_491dd327.

pub type LogMode {
  Replace
  Append
}
