//// linear_mutation_parse.gleam
//// Parse concern for linear_mutation (LOC hygiene split).
//// Response heuristics + three-line dump parsing.
//// Zero intentional behavior change.

import gleam/string
import grkr/progress/linear_mutation_policy
import grkr/progress/linear_mutation_types.{
  type MutationResult, MutationFailed, MutationStateUpdateSuccess, MutationSuccess,
}

pub fn mutation_result_from_response(response: String) -> MutationResult {
  let trimmed = string.trim(response)
  let lower = string.lowercase(trimmed)

  // Strict: top-level "errors" array JSON shape only (not bare word in messages).
  case has_top_level_errors_array(trimmed, lower) {
    True -> {
      case linear_mutation_policy.is_idempotent_error(response) {
        True -> MutationSuccess("idempotent-duplicate")
        False -> MutationFailed("Linear mutation returned errors")
      }
    }
    False -> {
      // Comment success: require commentCreate section + id under it.
      case extract_comment_id(trimmed, lower) {
        Ok(cid) ->
          MutationSuccess(case cid {
            "" -> "created"
            c -> c
          })
        Error(_) ->
          case is_state_update_success(lower) {
            True -> MutationStateUpdateSuccess
            // Unrecognized shapes must not become false "applied"
            False -> MutationFailed("unrecognized Linear mutation response")
          }
      }
    }
  }
}

fn has_top_level_errors_array(resp: String, lower: String) -> Bool {
  // JSON-ish top level errors array: "errors":[ or "errors": [  or starts-with {"errors"
  string.contains(lower, "\"errors\":[")
  || string.contains(lower, "\"errors\": [")
  || string.contains(lower, "\"errors\" :[")
  || string.contains(lower, "\"errors\" : [")
  || string.starts_with(string.trim(resp), "{\"errors\"")
  || string.contains(lower, "{\"errors\":[")
}

fn is_state_update_success(lower: String) -> Bool {
  // Require issueUpdate section + explicit success:true (space tolerant).
  case string.contains(lower, "issueupdate") {
    True ->
      string.contains(lower, "\"success\":true")
      || string.contains(lower, "\"success\": true")
      || string.contains(lower, "\"success\" :true")
      || string.contains(lower, "\"success\" : true")
    False -> False
  }
}

fn extract_comment_id(resp: String, lower: String) -> Result(String, Nil) {
  case string.contains(lower, "commentcreate") {
    True -> {
      let id = extract_id_after_section(resp, "commentCreate")
      case id {
        "" -> {
          // fallback to simple near "comment" only after confirming shape
          let cid = extract_first_quoted_id_after(resp, "\"comment\"")
          case cid {
            "" -> Ok("created")
            c -> Ok(c)
          }
        }
        c -> Ok(c)
      }
    }
    False -> Error(Nil)
  }
}

fn extract_id_after_section(response: String, section: String) -> String {
  let lower = string.lowercase(response)
  let sec_lower = string.lowercase(section)
  case string.contains(lower, sec_lower) {
    False -> ""
    True -> {
      // Take text after first occurrence of section and find first id value.
      let parts = string.split(response, section)
      case parts {
        [_, after, ..] -> extract_first_quoted_id(after)
        _ -> ""
      }
    }
  }
}

fn extract_first_quoted_id(s: String) -> String {
  let parts = string.split(s, "\"id\":\"")
  case parts {
    [_, after, ..] -> {
      case string.split(after, "\"") {
        [id, ..] -> id
        _ -> ""
      }
    }
    _ -> ""
  }
}

fn extract_first_quoted_id_after(response: String, marker: String) -> String {
  let lower = string.lowercase(response)
  case string.contains(lower, string.lowercase(marker)) {
    False -> ""
    True -> {
      let parts = string.split(response, marker)
      case parts {
        [_, after, ..] -> extract_first_quoted_id(after)
        _ -> ""
      }
    }
  }
}

/// Alias for the three-line dump parser (used by apply + tests).
pub fn parse_three_line_dump(
  content: String,
) -> Result(#(String, String, String), String) {
  parse_mutation_dump(content)
}

/// Parse a three-line dump (query\nvariables_json\nkey) or name-only form.
/// Returns Ok(#(query, vars, key)) for full; Error for name-only or invalid.
pub fn parse_mutation_dump(
  content: String,
) -> Result(#(String, String, String), String) {
  let lines = string.split(string.trim(content), "\n")
  case lines {
    [q, v, k] ->
      case string.starts_with(q, "TARGET_STATE=") {
        True -> Error("name-only:" <> content)
        False -> Ok(#(q, v, k))
      }
    [first, ..] ->
      case string.starts_with(first, "TARGET_STATE=") {
        True -> Error("name-only:" <> content)
        False ->
          case list_length(lines) >= 3 {
            True -> {
              // tolerate extra newlines
              let q = case lines {
                [qq, ..] -> qq
                _ -> ""
              }
              let v = case lines {
                [_, vv, ..] -> vv
                _ -> ""
              }
              let k = case lines {
                [_, _, kk, ..] -> kk
                _ -> ""
              }
              case q {
                "" -> Error("invalid dump")
                _ -> Ok(#(q, v, k))
              }
            }
            False -> Error("invalid dump: " <> content)
          }
      }
    _ -> Error("invalid dump: " <> content)
  }
}

fn list_length(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}
