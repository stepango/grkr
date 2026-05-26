/// Persist logic for task logs (sharded or not) with exact bash parity (split -l, manifest, append/replace, mktemp).
/// Split per t_491dd327. Uses core for emit/shard fns.

import gleam/int
import gleam/list
import gleam/string
import grkr/workflow/ffi as w
import grkr/workflow/task_log_core as core
import grkr/workflow/task_log_types.{type LogMode, Append, Replace}

pub fn persist_task_log_output(
  run: String,
  target: String,
  phase: String,
  mode: LogMode,
) -> Nil {
  let maxl =
    case w.tl_get_env("MAX_FILE_LINES") {
      "" -> 1000
      s ->
        case int.parse(string.trim(s)) {
          Ok(n) if n > 0 -> n
          _ -> 1000
        }
    }
  case core.supports_sharding(target) {
    False -> non_shard(run, target, phase, mode)
    True -> sharded(run, target, phase, mode, maxl)
  }
}

fn non_shard(run: String, target: String, phase: String, mode: LogMode) -> Nil {
  let rc = read_or(run)
  case mode, w.tl_exists(target) {
    Append, True -> {
      let h = "\n[grkr " <> phase <> "]\n\n"
      let ex = read_or(target)
      let _ = w.tl_write_text(target, ex <> h <> rc)
      let _ = w.tl_unlink_file(run)
      Nil
    }
    _, _ -> {
      let _ = w.tl_write_text(target, rc)
      let _ = w.tl_unlink_file(run)
      Nil
    }
  }
}

fn sharded(
  run: String,
  target: String,
  phase: String,
  mode: LogMode,
  maxl: Int,
) -> Nil {
  let comb = w.tl_temp_path("grkr-task-log.")
  let da =
    case mode {
      Append -> w.tl_exists(target) || core.is_sharded(target)
      _ -> False
    }
  let _ =
    case da {
      True -> {
        let pr = core.emit_task_log_stream(target)
        let h =
          case string.trim(pr) {
            "" -> ""
            _ -> "\n[grkr " <> phase <> "]\n\n"
          }
        let _ = w.tl_write_text(comb, pr <> h <> read_or(run))
        Nil
      }
      False -> {
        let _ = w.tl_write_text(comb, read_or(run))
        Nil
      }
    }
  let full = read_or(comb)
  let lc = core.count_lines(full)
  case lc <= maxl {
    True -> {
      let _ = w.tl_write_text(target, full)
      let _ = w.tl_remove_recursive(core.parts_dir(target))
      let _ = w.tl_unlink_file(run)
      let _ = w.tl_unlink_file(comb)
      Nil
    }
    False -> {
      let pd = core.parts_dir(target)
      let _ = w.tl_remove_recursive(pd)
      let _ = w.tl_mkdir_p(pd)
      let parts = core.make_shard_parts(full, maxl)
      list.index_map(parts, fn(pt, i) {
        let nm = pd <> "/part-" <> core.pad(i)
        let _ = w.tl_write_text(nm, pt)
        Nil
      })
      let _ = core.write_task_log_manifest(target, lc)
      let _ = w.tl_unlink_file(comb)
      let _ = w.tl_unlink_file(run)
      Nil
    }
  }
}

fn read_or(p: String) -> String {
  case w.tl_read_text(p) {
    Ok(c) -> c
    Error(_) -> ""
  }
}
