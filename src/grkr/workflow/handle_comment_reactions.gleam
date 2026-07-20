//// handle_comment_reactions.gleam
//// Eyes + rocket reaction helpers for @robot: comment handler (LOC hygiene).
//// Moved verbatim; best-effort semantics unchanged.

import grkr/workflow/ffi.{ExecResult}
import grkr/workflow/handle_comment_context as ctx

pub fn add_eyes_reaction(comment_id: String, repo: String) -> String {
  let path = "repos/" <> repo <> "/issues/comments/" <> comment_id <> "/reactions"
  let cmd = ["gh", "api", "-X", "POST", path, "-f", "content=eyes"]
  case ctx.run_gh(cmd) {
    ExecResult(0, out, _) -> {
      case ffi.parse(out) {
        Ok(root) -> case ffi.get_field(root, "id") |> ffi.decode_string {
          Ok(id) -> {
            let _ = ffi.console_log("   + eyes reaction (id=" <> id <> ")")
            id
          }
          _ -> {
            let _ = ffi.console_log("   ⚠️ eyes reaction add skipped/failed (best effort)")
            ""
          }
        }
        _ -> ""
      }
    }
    _ -> {
      let _ = ffi.console_log("   ⚠️ eyes reaction add skipped/failed (best effort)")
      ""
    }
  }
}

pub fn remove_eyes_and_add_rocket(comment_id: String, repo: String, eyes_id: String) -> Nil {
  case eyes_id {
    "" -> Nil
    id -> {
      let del = ["gh", "api", "-X", "DELETE", "repos/" <> repo <> "/issues/comments/" <> comment_id <> "/reactions/" <> id]
      let _ = ctx.run_gh(del)
      Nil
    }
  }
  let rocket = ["gh", "api", "-X", "POST", "repos/" <> repo <> "/issues/comments/" <> comment_id <> "/reactions", "-f", "content=rocket"]
  case ctx.run_gh(rocket) {
    ExecResult(0, _, _) -> ffi.console_log("   + rocket reaction (success path)")
    _ -> ffi.console_log("   ⚠️ rocket reaction add failed (best effort)")
  }
}
