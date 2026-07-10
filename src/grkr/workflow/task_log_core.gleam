/// Core task log fns for sharding detection, emit, manifest (GitHub-only v2).
/// Split per t_491dd327 / AGENTS (from monolithic task_log.gleam).
/// Pure query + string helpers + manifest; no top level persist.

import gleam/int
import gleam/list
import gleam/string
import grkr/workflow/ffi as w

pub fn supports_sharding(p: String) -> Bool {
  string.contains(p, "/.grkr/tasks/") && string.ends_with(p, "/implementation.log")
}

pub fn parts_dir(p: String) -> String {
  dirname(p) <> "/codex/" <> basename(p) <> ".parts"
}

pub fn is_sharded(p: String) -> Bool {
  let pd = parts_dir(p)
  w.tl_exists(pd) && w.tl_exists(pd <> "/part-0000")
}

pub fn emit_task_log_stream(p: String) -> String {
  case is_sharded(p) {
    True -> {
      let pd = parts_dir(p)
      case w.tl_list_files(pd) {
        Ok(fs) ->
          fs
          |> list.filter(fn(f) { string.starts_with(f, "part-") })
          |> list.sort(string.compare)
          |> list.map(fn(f) {
            case w.tl_read_text(pd <> "/" <> f) {
              Ok(c) -> c
              Error(_) -> ""
            }
          })
          |> string.join("")
        Error(_) -> ""
      }
    }
    False ->
      case w.tl_exists(p) {
        True ->
          case w.tl_read_text(p) {
            Ok(c) -> c
            Error(_) -> ""
          }
        False -> ""
      }
  }
}

pub fn write_task_log_manifest(target: String, lc: Int) -> Nil {
  write_manifest(target, lc)
}

fn write_manifest(target: String, lc: Int) -> Nil {
  let maxl =
    case w.tl_get_env("MAX_FILE_LINES") {
      "" -> 1000
      s ->
        case int.parse(string.trim(s)) {
          Ok(n) if n > 0 -> n
          _ -> 1000
        }
    }
  let pd = parts_dir(target)
  let base = basename(target)
  let ents =
    case w.tl_list_files(pd) {
      Ok(fs) -> {
        let ps =
          fs
          |> list.filter(fn(f) { string.starts_with(f, "part-") })
          |> list.sort(string.compare)
        case ps {
          [] -> "- `(no parts written)`\n"
          _ ->
            ps
            |> list.map(fn(f) {
              "- `codex/" <> base <> ".parts/" <> f <> "`\n"
            })
            |> string.join("")
        }
      }
      Error(_) -> "- `(no parts written)`\n"
    }
  let m =
    "# Sharded Codex Output\n\nThe full transcript exceeded the repository "
    <> int.to_string(maxl)
    <> "-line limit, so grkr stored it in numbered parts.\n\n- Stable entrypoint: `"
    <> base
    <> "`\n- Total lines: "
    <> int.to_string(lc)
    <> "\n- Part size: up to "
    <> int.to_string(maxl)
    <> " lines\n\n## Parts\n\n"
    <> ents
  let _ = w.tl_write_text(target, m)
  Nil
}

pub fn pad(n: Int) -> String {
  let s = int.to_string(n)
  case string.length(s) {
    1 -> "000" <> s
    2 -> "00" <> s
    3 -> "0" <> s
    _ -> s
  }
}

fn dirname(p: String) -> String {
  let ps = string.split(p, "/")
  case list.length(ps) {
    0 | 1 -> "."
    _ -> {
      let n = list.length(ps) - 1
      ps |> list.take(n) |> string.join("/")
    }
  }
}

fn basename(p: String) -> String {
  case
    string.split(p, "/")
    |> list.reverse
    |> list.first
  {
    Ok(b) -> b
    Error(_) -> p
  }
}

pub fn count_lines(c: String) -> Int {
  // exact match to shell `wc -l` (counts \n chars after \r\n norm)
  let norm = string.replace(c, "\r\n", "\n")
  let ps = string.split(norm, "\n")
  list.length(ps) - 1
}

/// Produce list of part file contents (exact bytes) that match `split -l N -d -a4` behavior
/// so wc -l per part and cat concat == original full transcript.
pub fn make_shard_parts(full: String, maxl: Int) -> List(String) {
  let norm = string.replace(full, "\r\n", "\n")
  let ps = string.split(norm, "\n")
  let total = list.length(ps) - 1
  case total <= 0 {
    True -> []
    False -> do_make_parts(ps, maxl, 0, total, [])
  }
}

fn do_make_parts(
  ps: List(String),
  maxl: Int,
  start: Int,
  total: Int,
  acc: List(String),
) -> List(String) {
  let remain = total - start
  case remain <= 0 {
    True -> list.reverse(acc)
    False -> {
      let k = int.min(maxl, remain)
      let chunk_lines = list.drop(ps, start) |> list.take(k)
      let base = string.join(chunk_lines, "\n")
      let is_last = start + k >= total
      let ends_trailing_nl =
        case list.last(ps) {
          Ok("") -> True
          _ -> False
        }
      let part =
        case is_last {
          True ->
            case ends_trailing_nl {
              True -> base <> "\n"
              False -> base
            }
          False -> base <> "\n"
        }
      do_make_parts(ps, maxl, start + k, total, [part, ..acc])
    }
  }
}
