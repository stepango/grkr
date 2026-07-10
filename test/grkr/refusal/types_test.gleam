import gleeunit
import gleeunit/should
import gleam/string
import grkr/refusal/types.{
  Other, Underspecified, TooLarge, MissingDependency,
  NeedsDesignDecision, UnsafeAutonomousChange, RepoNotReady,
  normalize_refusal_class, from_string, to_string, to_display_name,
  default_class, parse_implementation_decision, Proceed, Refuse,
}

pub fn main() {
  gleeunit.main()
}

pub fn normalize_refusal_class_test() {
  normalize_refusal_class("underspecified")
  |> should.equal(Underspecified)

  normalize_refusal_class("Too Large")
  |> should.equal(TooLarge)

  normalize_refusal_class("missing-dependency")
  |> should.equal(MissingDependency)

  normalize_refusal_class("needs_design_decision")
  |> should.equal(NeedsDesignDecision)

  normalize_refusal_class("unsafe_autonomous_change")
  |> should.equal(UnsafeAutonomousChange)

  normalize_refusal_class("repo_not_ready")
  |> should.equal(RepoNotReady)

  normalize_refusal_class("other")
  |> should.equal(Other("other"))

  normalize_refusal_class("invalid foo bar")
  |> should.equal(Other("invalid_foo_bar"))

  normalize_refusal_class("")
  |> should.equal(Other(""))
}

pub fn from_string_test() {
  from_string("underspecified")
  |> should.equal(Ok(Underspecified))

  from_string("invalid")
  |> should.be_error()
}

pub fn to_string_test() {
  to_string(Underspecified) |> should.equal("underspecified")
  to_string(TooLarge) |> should.equal("too_large")
  to_string(Other("foo")) |> should.equal("foo")
  to_string(Other("other")) |> should.equal("other")
}

pub fn to_display_name_test() {
  to_display_name(Underspecified)
  |> should.equal("underspecified (acceptance criteria unclear)")

  to_display_name(Other("custom"))
  |> should.equal("other: custom")
}

pub fn default_class_test() {
  default_class() |> should.equal(Underspecified)
}

pub fn parse_implementation_decision_test() {
  // proceed case
  parse_implementation_decision("proceed with impl\nsome reason")
  |> should.equal(Proceed)

  // refuse case
  let decision =
    parse_implementation_decision("refuse\nunderspecified\nThe acceptance criteria are missing.\nNeed examples.")
  case decision {
    Refuse(class, reason) -> {
      class |> should.equal(Underspecified)
      // reason has the rest
      string.contains(reason, "The acceptance criteria") |> should.be_true()
    }
    _ -> should.fail()
  }

  // default to other
  parse_implementation_decision("refuse\nweird class\nreason here")
  |> should.equal(Refuse(Other("weird_class"), "reason here"))
}
