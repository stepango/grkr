import gleam/list
import gleam/string

/// Normalize a status option name for case-insensitive comparison.
/// Trims leading/trailing whitespace, collapses internal whitespace to single spaces,
/// and converts to lowercase.
pub fn normalize_option_name(name: String) -> String {
  name
  |> string.trim()
  |> split_whitespace()
  |> list.filter(fn(s) { !string.is_empty(s) })
  |> string.join(" ")
  |> string.lowercase()
}

/// Split a string on whitespace
fn split_whitespace(s: String) -> List(String) {
  string.split(s, " ")
  |> list.flat_map(fn(part) {
    case part {
      "" -> []
      _ ->
        string.split(part, "\n")
        |> list.flat_map(fn(p) {
          case p {
            "" -> []
            _ -> string.split(p, "\t")
          }
        })
    }
  })
}

/// Check if two status names match after normalization
pub fn names_match(a: String, b: String) -> Bool {
  normalize_option_name(a) == normalize_option_name(b)
}

/// Trim and collapse whitespace without changing case
pub fn trim_and_collapse(s: String) -> String {
  s
  |> string.trim()
  |> split_whitespace()
  |> list.filter(fn(s) { !string.is_empty(s) })
  |> string.join(" ")
}
