/// Task log facade (reexports fns + CLI entrypoint).
/// GitHub-only v2. Split into small modules per AGENTS + t_491dd327.
/// Public API for fns unchanged so most callers (bin thin sh, main) need zero changes.
/// -m grkr/workflow/task_log still works. Test updated to import LogMode variants from task_log_types (small).

import grkr/workflow/task_log_cli as cli
import grkr/workflow/task_log_core as core
import grkr/workflow/task_log_persist as persist

pub fn supports_sharding(p: String) -> Bool {
  core.supports_sharding(p)
}

pub fn parts_dir(p: String) -> String {
  core.parts_dir(p)
}

pub fn is_sharded(p: String) -> Bool {
  core.is_sharded(p)
}

pub fn emit_task_log_stream(p: String) -> String {
  core.emit_task_log_stream(p)
}

pub fn persist_task_log_output(
  run: String,
  target: String,
  phase: String,
  mode,
) -> Nil {
  persist.persist_task_log_output(run, target, phase, mode)
}

pub fn write_task_log_manifest(target: String, lc: Int) -> Nil {
  core.write_task_log_manifest(target, lc)
}

pub fn main() -> Nil {
  cli.main()
}
