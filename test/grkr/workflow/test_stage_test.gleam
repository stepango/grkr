import gleeunit
import gleeunit/should
import grkr/workflow/test_stage

pub fn main() {
  gleeunit.main()
}

pub fn test_hook_message_test() {
  test_stage.test_hook_message()
  |> should.equal("🧪 test_stage run-tests hook (delegated to shell per spec/26; exit 0)")
}

pub fn completion_marker_test() {
  test_stage.completion_marker("issue-123-add-search-index")
  |> should.equal("<!-- grkr:checkpoint stage=test task=issue-123-add-search-index version=1 -->")

  test_stage.completion_marker("my-slug")
  |> should.equal("<!-- grkr:checkpoint stage=test task=my-slug version=1 -->")

  // trims per impl
  test_stage.completion_marker("  foo-bar  ")
  |> should.equal("<!-- grkr:checkpoint stage=test task=foo-bar version=1 -->")
}
