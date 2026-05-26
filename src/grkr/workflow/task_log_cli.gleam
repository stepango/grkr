/// CLI entry for task_log (persist/emit/is-sharded etc).
/// Invoked as: gleam run -m grkr/workflow/task_log -- persist ...
/// Split per t_491dd327; thin facade keeps the -m name stable.

import gleam/int
import gleam/string
import grkr/workflow/ffi as w
import grkr/workflow/task_log_core as core
import grkr/workflow/task_log_persist as persist
import grkr/workflow/task_log_types.{type LogMode, Append, Replace}

pub fn main() -> Nil {
  case w.argv() {
    ["persist", run, target, phase, mstr] -> {
      let m = case mstr {
        "append" -> Append
        _ -> Replace
      }
      persist.persist_task_log_output(run, target, phase, m)
      w.exit(0)
    }
    ["emit", p] -> {
      let s = core.emit_task_log_stream(p)
      let _ = w.tl_stdout_write(s)
      w.exit(0)
    }
    ["is-sharded", p] -> {
      case core.is_sharded(p) {
        True -> w.exit(0)
        False -> w.exit(1)
      }
    }
    ["supports-sharding", p] -> {
      case core.supports_sharding(p) {
        True -> w.exit(0)
        False -> w.exit(1)
      }
    }
    ["parts-dir", p] -> {
      w.console_log(core.parts_dir(p))
      w.exit(0)
    }
    ["write-manifest", target, lc_str] -> {
      case int.parse(lc_str) {
        Ok(lc) -> {
          core.write_task_log_manifest(target, lc)
          w.exit(0)
        }
        _ -> {
          w.console_error("invalid lc for write-manifest")
          w.exit(2)
        }
      }
    }
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() -> Nil {
  w.console_error(
    "Usage: gleam run -m grkr/workflow/task_log -- persist <run> <target> <phase> <replace|append>",
  )
  w.console_error(
    "       gleam run -m grkr/workflow/task_log -- emit <path>",
  )
  w.console_error(
    "       gleam run -m grkr/workflow/task_log -- is-sharded <path>",
  )
  w.console_error(
    "       gleam run -m grkr/workflow/task_log -- supports-sharding <path>",
  )
  w.console_error(
    "       gleam run -m grkr/workflow/task_log -- parts-dir <path>",
  )
  w.console_error(
    "       gleam run -m grkr/workflow/task_log -- write-manifest <target> <linecount>",
  )
  w.console_error("       gleam run -m grkr/workflow/task_log -- help")
  w.console_error("")
  w.console_error(
    "Task log sharding/persist/emit CLI (GitHub-only v2). Exact parity with old bash for codex outputs >1000 lines.",
  )
  w.exit(2)
}
