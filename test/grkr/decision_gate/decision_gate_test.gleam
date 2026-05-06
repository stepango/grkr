import gleam/string
import gleeunit
import gleeunit/should
import grkr/decision_gate/decision
import grkr/decision_gate/main
import grkr/decision_gate/prompt
import grkr/decision_gate/refusal
import grkr/decision_gate/types

pub fn main() {
  gleeunit.main()
}

// Decision parsing tests

pub fn decision_parse_proceed_test() {
  let output = "\n  PROCEED  \nmore text"
  let result = decision.parse_decision(output)

  result
  |> should.equal(Ok(types.Proceed))
}

pub fn decision_parse_refuse_test() {
  let output = "\nrefuse\nmore text"
  let result = decision.parse_decision(output)

  result
  |> should.equal(Ok(types.Refuse))
}

pub fn decision_parse_case_insensitive_test() {
  let output = "PROCEED"
  let result = decision.parse_decision(output)

  result
  |> should.equal(Ok(types.Proceed))
}

pub fn decision_parse_empty_test() {
  let output = "Some text but no decision"
  let result = decision.parse_decision(output)

  result
  |> should.equal(Error(Nil))
}

pub fn decision_parse_rejects_later_decision_test() {
  let output = "I need to explain first\nproceed"
  let result = decision.parse_decision(output)

  result
  |> should.equal(Error(Nil))
}

pub fn decision_normalize_proceed_test() {
  let result = decision.normalize_decision("PROCEED")
  result
  |> should.equal(types.Proceed)
}

pub fn decision_normalize_refuse_test() {
  let result = decision.normalize_decision("refuse")
  result
  |> should.equal(types.Refuse)
}

pub fn decision_normalize_invalid_defaults_to_refuse_test() {
  let result = decision.normalize_decision("invalid")
  result
  |> should.equal(types.Refuse)
}

pub fn decision_is_valid_test() {
  decision.is_valid_decision("proceed")
  |> should.be_true

  decision.is_valid_decision("refuse")
  |> should.be_true

  decision.is_valid_decision("PROCEED")
  |> should.be_true

  decision.is_valid_decision("invalid")
  |> should.be_false
}

// Refusal parsing tests

pub fn refusal_parse_details_test() {
  let output =
    "refuse\nunderspecified\nThe issue lacks clear acceptance criteria"
  let result = refusal.parse_refusal_details(output)

  result
  |> should.equal(
    Ok(types.RefusalDetails(
      class: types.Underspecified,
      reasoning: "The issue lacks clear acceptance criteria",
    )),
  )
}

pub fn refusal_parse_with_empty_lines_test() {
  let output =
    "refuse\n\n\nunderspecified\n\nThe issue lacks clear acceptance criteria"
  let result = refusal.parse_refusal_details(output)

  result
  |> should.equal(
    Ok(types.RefusalDetails(
      class: types.Underspecified,
      reasoning: "The issue lacks clear acceptance criteria",
    )),
  )
}

pub fn refusal_parse_no_class_defaults_to_other_test() {
  let output = "refuse\n\nSome reasoning but no class"
  let result = refusal.parse_refusal_details(output)

  case result {
    Ok(types.RefusalDetails(class: types.Other, reasoning: r)) -> {
      r
      |> should.equal("Some reasoning but no class")
    }
    _ -> {
      let _ = result
      "Should have defaulted to Other"
      |> should.equal("Some reasoning but no class")
    }
  }
}

pub fn refusal_normalize_class_test() {
  refusal.normalize_refusal_class("underspecified")
  |> should.equal(types.Underspecified)

  refusal.normalize_refusal_class("TOO_LARGE")
  |> should.equal(types.TooLarge)

  refusal.normalize_refusal_class("missing-dependency")
  |> should.equal(types.MissingDependency)

  refusal.normalize_refusal_class("unknown")
  |> should.equal(types.Other)
}

pub fn refusal_is_valid_class_test() {
  refusal.is_valid_refusal_class("underspecified")
  |> should.be_true

  refusal.is_valid_refusal_class("too_large")
  |> should.be_true

  refusal.is_valid_refusal_class("invalid")
  |> should.be_false
}

pub fn refusal_default_reasoning_test() {
  let reasoning = refusal.default_refusal_reasoning()
  string.starts_with(reasoning, "The issue does not appear ready")
  |> should.be_true
}

// Decision gate main tests

pub fn decision_gate_proceed_test() {
  let output = "proceed"
  let result = main.run_decision_gate(output)

  result
  |> should.equal(types.DecisionProceeded)
}

pub fn decision_gate_refuse_test() {
  let output = "refuse\nunderspecified\nIssue is unclear"
  let result = main.run_decision_gate(output)

  case result {
    types.DecisionRefused(types.RefusalDetails(
      class: types.Underspecified,
      reasoning: r,
    )) -> {
      r
      |> should.equal("Issue is unclear")
    }
    _ -> {
      let _ = result
      "Should have refused with Underspecified class"
      |> should.equal("Issue is unclear")
    }
  }
}

pub fn decision_gate_invalid_defaults_to_refuse_test() {
  let output = "invalid output with no decision"
  let result = main.run_decision_gate(output)

  case result {
    types.DecisionRefused(types.RefusalDetails(class: types.Other, reasoning: _)) -> {
      let _ = result
      result
      |> should.equal(
        types.DecisionRefused(types.RefusalDetails(
          class: types.Other,
          reasoning: "Decision gate returned an invalid result. Defaulting to refuse for safety.",
        )),
      )
    }
    _ -> {
      let _ = result
      "Should have defaulted to refuse"
      |> should.equal("This test should not reach this branch")
    }
  }
}

pub fn decision_gate_is_proceed_test() {
  main.is_proceed(types.DecisionProceeded)
  |> should.be_true

  main.is_proceed(
    types.DecisionRefused(types.RefusalDetails(
      class: types.Other,
      reasoning: "",
    )),
  )
  |> should.be_false
}

pub fn decision_gate_is_refuse_test() {
  main.is_refuse(
    types.DecisionRefused(types.RefusalDetails(
      class: types.Other,
      reasoning: "",
    )),
  )
  |> should.be_true

  main.is_refuse(types.DecisionProceeded)
  |> should.be_false
}

pub fn decision_gate_get_refusal_details_test() {
  let result =
    types.DecisionRefused(types.RefusalDetails(
      class: types.Underspecified,
      reasoning: "Test reasoning",
    ))

  case main.get_refusal_details(result) {
    Ok(types.RefusalDetails(class: types.Underspecified, reasoning: r)) -> {
      r
      |> should.equal("Test reasoning")
    }
    _ -> {
      let _ = result
      "Should have returned refusal details"
      |> should.equal("Test reasoning")
    }
  }
}

pub fn decision_gate_result_to_string_test() {
  main.decision_result_to_string(types.DecisionProceeded)
  |> should.equal("proceed")

  main.decision_result_to_string(
    types.DecisionRefused(types.RefusalDetails(
      class: types.Other,
      reasoning: "",
    )),
  )
  |> should.equal("refuse")
}

pub fn refusal_missing_requirements_test() {
  let req = refusal.missing_requirements(types.Underspecified)
  string.contains(req, "acceptance criteria")
  |> should.be_true
}

pub fn refusal_next_steps_test() {
  let steps = refusal.next_steps(types.TooLarge)
  string.contains(steps, "Split the issue")
  |> should.be_true
}

pub fn refusal_split_recommendation_test() {
  let rec = refusal.split_recommendation(types.TooLarge)
  string.contains(rec, "Yes")
  |> should.be_true
}

pub fn refusal_follow_up_recommendation_test() {
  let rec = refusal.follow_up_recommendation(types.TooLarge)
  string.contains(rec, "Yes")
  |> should.be_true
}

pub fn prompt_includes_issue_and_checkpoint_context_test() {
  let context =
    main.create_context(
      15,
      "Add decision gate",
      "https://github.com/stepango/grkr/issues/15",
      "Gate must refuse unsafe work",
      "/repo",
      "/repo/.grkr/worktrees/issue-15",
      "issue-15-add-decision-gate",
      1000,
    )
  let built = prompt.build_decision_prompt(context)

  string.contains(built, "Issue #15: Add decision gate")
  |> should.be_true
  string.contains(
    built,
    "/repo/.grkr/tasks/issue-15-add-decision-gate/research.md",
  )
  |> should.be_true
  string.contains(built, "proceed or refuse")
  |> should.be_true
  string.contains(built, "1000 lines or fewer")
  |> should.be_true
}

pub fn implementation_refusal_marker_parse_test() {
  let output =
    "work log\ngrkr-refuse-implementation\nmissing_dependency\nNeed upstream API first"
  let result = refusal.parse_implementation_refusal(output)

  result
  |> should.equal(
    Ok(types.RefusalDetails(
      class: types.MissingDependency,
      reasoning: "Need upstream API first",
    )),
  )
}

pub fn implementation_refusal_missing_marker_test() {
  refusal.parse_implementation_refusal("ordinary implementation output")
  |> should.equal(Error(Nil))
}
