import gleam/int
import gleam/list
import gleam/string

const max_title_slug_length = 80

pub fn slugify_text(text: String) -> String {
  text
  |> string.lowercase
  |> replace_non_alphanumeric_with_dash
  |> collapse_repeated_dashes
  |> trim_leading_and_trailing_dashes
  |> truncate_to_max_length
}

pub fn task_slug_for_issue(issue_number: Int, title: String) -> String {
  let title_slug = slugify_text(title)

  let fallback = case title_slug {
    "" -> "task"
    _ -> title_slug
  }

  "issue-" <> int.to_string(issue_number) <> "-" <> fallback
}

fn replace_non_alphanumeric_with_dash(text: String) -> String {
  text
  |> string.to_graphemes
  |> list.map(fn(char) {
    case is_ascii_alphanumeric(char) {
      True -> char
      False -> "-"
    }
  })
  |> string.join("")
}

fn is_ascii_alphanumeric(char: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789", char)
}

fn collapse_repeated_dashes(text: String) -> String {
  text
  |> string.to_graphemes
  |> list.fold("", fn(acc, char) {
    case acc, char {
      "", "-" -> {
        ""
      }
      _, "-" -> {
        case string.ends_with(acc, "-") {
          True -> acc
          False -> acc <> char
        }
      }
      _, _ -> acc <> char
    }
  })
}

fn trim_leading_and_trailing_dashes(text: String) -> String {
  text
  |> trim_leading_dashes
  |> trim_trailing_dashes
}

fn trim_leading_dashes(text: String) -> String {
  case string.starts_with(text, "-") {
    True ->
      text
      |> string.slice(1, string.length(text) - 1)
      |> trim_leading_dashes
    False -> text
  }
}

fn trim_trailing_dashes(text: String) -> String {
  case string.ends_with(text, "-") {
    True ->
      text
      |> string.slice(0, string.length(text) - 1)
      |> trim_trailing_dashes
    False -> text
  }
}

fn truncate_to_max_length(text: String) -> String {
  string.slice(text, 0, max_title_slug_length)
}
