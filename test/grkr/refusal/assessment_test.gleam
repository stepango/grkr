import gleeunit
import gleeunit/should
import gleam/string
import gleam/option.{Some}
import grkr/refusal/assessment
import grkr/refusal/types.{Underspecified, TooLarge, MissingDependency, NeedsDesignDecision, UnsafeAutonomousChange, RepoNotReady, Other}

pub fn main() {
  gleeunit.main()
}

pub fn missing_requirements_test() {
  string.contains(assessment.missing_requirements_markdown(Underspecified), "Explicit acceptance criteria")
  |> should.be_true()

  string.contains(assessment.missing_requirements_markdown(TooLarge), "smaller, explicitly scoped")
  |> should.be_true()

  string.contains(assessment.missing_requirements_markdown(Other("foo")), "missing prerequisite identified")
  |> should.be_true()
}

pub fn next_steps_test() {
  string.contains(assessment.next_steps_markdown(TooLarge), "Split the issue")
  |> should.be_true()

  string.contains(assessment.next_steps_markdown(Underspecified), "Update the issue with the missing detail")
  |> should.be_true()
}

pub fn split_recommendation_test() {
  string.contains(assessment.split_recommendation(TooLarge), "Yes. The current issue is too broad")
  |> should.be_true()

  string.contains(assessment.split_recommendation(Underspecified), "No immediate split is required")
  |> should.be_true()
}

pub fn follow_up_recommendation_test() {
  string.contains(assessment.follow_up_recommendation(MissingDependency), "Yes. Follow-up issues are recommended")
  |> should.be_true()

  string.contains(assessment.follow_up_recommendation(RepoNotReady), "Not necessarily")
  |> should.be_true()
}

pub fn format_full_refusal_md_test() {
  let md = assessment.format_full_refusal_md(
    "test-slug-123",
    Some(42),
    "Example Issue Title",
    Underspecified,
    "Acceptance criteria are vague.",
  )

  string.contains(md, "<!-- grkr:checkpoint stage=refusal task=test-slug-123 version=1 -->")
  |> should.be_true()

  string.contains(md, "Issue #42: Example Issue Title")
  |> should.be_true()

  string.contains(md, "### Reason class\n\nunderspecified")
  |> should.be_true()

  string.contains(md, "Detailed reasoning\n\nAcceptance criteria are vague.")
  |> should.be_true()

  string.contains(md, "What is needed before implementation")
  |> should.be_true()

  string.contains(md, "Explicit acceptance criteria")
  |> should.be_true()

  string.contains(md, "Should the issue be split?")
  |> should.be_true()

  string.contains(md, "No immediate split")
  |> should.be_true()
}
