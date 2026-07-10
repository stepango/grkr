import gleam/string
import gleeunit
import gleeunit/should
import grkr/task_slug

pub fn main() {
  gleeunit.main()
}

pub fn slugify_text_lowercase_test() {
  task_slug.slugify_text("HELLO WORLD")
  |> should.equal("hello-world")
}

pub fn slugify_text_replaces_special_chars_test() {
  task_slug.slugify_text("Hello@World#Test!")
  |> should.equal("hello-world-test")
}

pub fn slugify_text_replaces_spaces_test() {
  task_slug.slugify_text("add search index")
  |> should.equal("add-search-index")
}

pub fn slugify_text_collapses_repeated_dashes_test() {
  task_slug.slugify_text("Hello---World")
  |> should.equal("hello-world")
}

pub fn slugify_text_trims_leading_dashes_test() {
  task_slug.slugify_text("-hello-world")
  |> should.equal("hello-world")
}

pub fn slugify_text_trims_trailing_dashes_test() {
  task_slug.slugify_text("hello-world-")
  |> should.equal("hello-world")
}

pub fn slugify_text_trims_both_leading_and_trailing_dashes_test() {
  task_slug.slugify_text("--hello-world--")
  |> should.equal("hello-world")
}

pub fn slugify_text_truncates_to_80_chars_test() {
  let long_text = "a" <> string.repeat("b", 100)

  let result = task_slug.slugify_text(long_text)

  string.length(result)
  |> should.equal(80)
}

pub fn slugify_text_punctuation_collapse_test() {
  task_slug.slugify_text("Fix: bug!!!")
  |> should.equal("fix-bug")
}

pub fn slugify_text_empty_after_processing_test() {
  task_slug.slugify_text("---")
  |> should.equal("")
}

pub fn slugify_text_unicode_ignored_test() {
  task_slug.slugify_text("café")
  |> should.equal("caf")
}

pub fn slugify_text_preserves_numbers_test() {
  task_slug.slugify_text("Version 2.0.1 released")
  |> should.equal("version-2-0-1-released")
}

pub fn task_slug_for_issue_normal_title_test() {
  task_slug.task_slug_for_issue(123, "Add search index")
  |> should.equal("issue-123-add-search-index")
}

pub fn task_slug_for_issue_with_punctuation_test() {
  task_slug.task_slug_for_issue(456, "Fix: bug in auth flow!!!")
  |> should.equal("issue-456-fix-bug-in-auth-flow")
}

pub fn task_slug_for_issue_empty_title_fallback_test() {
  task_slug.task_slug_for_issue(789, "")
  |> should.equal("issue-789-task")
}

pub fn task_slug_for_issue_non_sluggable_title_fallback_test() {
  task_slug.task_slug_for_issue(101, "!!!")
  |> should.equal("issue-101-task")
}

pub fn task_slug_for_issue_long_title_truncation_test() {
  let long_title =
    "This is a very long title that exceeds the maximum allowed length for a slug "
    <> "and should be truncated appropriately"

  let result = task_slug.task_slug_for_issue(999, long_title)

  string.slice(result, 0, 10)
  |> should.equal("issue-999-")

  string.length(result)
  |> should.equal(90)
  // "issue-999-" is 10 chars + 80 for title
}

pub fn task_slug_for_issue_preserves_issue_number_test() {
  task_slug.task_slug_for_issue(1, "Test")
  |> should.equal("issue-1-test")
}
