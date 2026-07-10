import gleeunit
import gleeunit/should
import gleam/string
import grkr/workflow/decision.{
  detect_implementation_refusal, extract_decision_from_output,
  parse_refusal_decision_output, update_task_progress_decision,
}

pub fn main() {
  gleeunit.main()
}

pub fn extract_decision_test() {
  extract_decision_from_output("Analysis complete.\nproceed")
  |> should.equal("proceed")

  extract_decision_from_output("some text\nrefuse\nmore")
  |> should.equal("refuse")

  extract_decision_from_output("no decision here")
  |> should.equal("")
}

pub fn parse_refusal_decision_test() {
  let input = "refuse\nunderspecified\nThe acceptance criteria are missing.\nNeed examples."
  let parsed = parse_refusal_decision_output(input)
  string.contains(parsed, "underspecified") |> should.be_true()
  string.contains(parsed, "---") |> should.be_true()
  string.contains(parsed, "The acceptance criteria") |> should.be_true()

  // no reason case
  parse_refusal_decision_output("refuse\nother\n")
  |> should.equal("other\n---\n")
}

pub fn detect_implementation_refusal_test() {
  let marker_output = "
## Analysis

The issue requires implementing feature X, but during implementation I discovered that API Y does not exist yet. This is a missing dependency blocker.

grkr-refuse-implementation
missing_dependency
The required upstream API does not exist in the codebase yet.
"
  let detected = detect_implementation_refusal(marker_output)
  string.contains(detected, "missing_dependency") |> should.be_true()
  string.contains(detected, "---") |> should.be_true()
  string.contains(detected, "upstream API") |> should.be_true()

  // false positive ordinary prose
  let prose = "## Implementation plan details\nRefuse broad rewrites."
  detect_implementation_refusal(prose)
  |> should.equal("")

  // Prompt documents the marker before codex emits the real refusal block.
  let prompt_then_refusal =
    "If blocked, end with:\ngrkr-refuse-implementation\n<class>\n<reason>\n\n## Analysis\n\ngrkr-refuse-implementation\nmissing_dependency\nBlocked on API.\n"
  let detected2 = detect_implementation_refusal(prompt_then_refusal)
  string.contains(detected2, "missing_dependency") |> should.be_true()
}

pub fn update_task_progress_decision_test() {
  let res = update_task_progress_decision("/tmp/nonexistent-for-test.json", "proceed")
  // FFI (unlike original bash jq on missing file) handles absent progress.json gracefully by starting from {}; always Ok for valid "proceed"/"refuse".
  // This is a smoke test (per prior impl card) that the fn runs and returns success path.
  case res {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}
