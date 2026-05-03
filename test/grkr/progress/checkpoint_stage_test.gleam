import gleeunit
import gleeunit/should
import grkr/progress/checkpoint_stage

pub fn main() {
  gleeunit.main()
}

pub fn from_string_test() {
  checkpoint_stage.from_string("research")
  |> should.equal(Ok(checkpoint_stage.Research))

  checkpoint_stage.from_string("plan")
  |> should.equal(Ok(checkpoint_stage.Plan))

  checkpoint_stage.from_string("refusal")
  |> should.equal(Ok(checkpoint_stage.Refusal))

  checkpoint_stage.from_string("implementation")
  |> should.equal(Ok(checkpoint_stage.Implementation))

  checkpoint_stage.from_string("test")
  |> should.equal(Ok(checkpoint_stage.Test))

  checkpoint_stage.from_string("pr_summary")
  |> should.equal(Ok(checkpoint_stage.PrSummary))

  checkpoint_stage.from_string("invalid")
  |> should.be_error()

  checkpoint_stage.from_string("RESEARCH")
  |> should.equal(Ok(checkpoint_stage.Research))
}

pub fn to_string_test() {
  checkpoint_stage.to_string(checkpoint_stage.Research)
  |> should.equal("research")

  checkpoint_stage.to_string(checkpoint_stage.Plan)
  |> should.equal("plan")

  checkpoint_stage.to_string(checkpoint_stage.Refusal)
  |> should.equal("refusal")

  checkpoint_stage.to_string(checkpoint_stage.Implementation)
  |> should.equal("implementation")

  checkpoint_stage.to_string(checkpoint_stage.Test)
  |> should.equal("test")

  checkpoint_stage.to_string(checkpoint_stage.PrSummary)
  |> should.equal("pr_summary")
}

pub fn to_display_name_test() {
  checkpoint_stage.to_display_name(checkpoint_stage.Research)
  |> should.equal("Research checkpoint")

  checkpoint_stage.to_display_name(checkpoint_stage.Plan)
  |> should.equal("Plan checkpoint")

  checkpoint_stage.to_display_name(checkpoint_stage.Refusal)
  |> should.equal("Implementation refused")

  checkpoint_stage.to_display_name(checkpoint_stage.Implementation)
  |> should.equal("Implementation checkpoint")

  checkpoint_stage.to_display_name(checkpoint_stage.Test)
  |> should.equal("Test checkpoint")

  checkpoint_stage.to_display_name(checkpoint_stage.PrSummary)
  |> should.equal("PR summary")
}

pub fn is_valid_stage_test() {
  checkpoint_stage.is_valid_stage("research")
  |> should.be_true()

  checkpoint_stage.is_valid_stage("plan")
  |> should.be_true()

  checkpoint_stage.is_valid_stage("invalid")
  |> should.be_false()
}

pub fn requires_linear_state_update_test() {
  checkpoint_stage.requires_linear_state_update(checkpoint_stage.Research)
  |> should.be_true()

  checkpoint_stage.requires_linear_state_update(checkpoint_stage.Plan)
  |> should.be_true()

  checkpoint_stage.requires_linear_state_update(checkpoint_stage.Refusal)
  |> should.be_false()

  checkpoint_stage.requires_linear_state_update(checkpoint_stage.Implementation)
  |> should.be_true()

  checkpoint_stage.requires_linear_state_update(checkpoint_stage.Test)
  |> should.be_true()

  checkpoint_stage.requires_linear_state_update(checkpoint_stage.PrSummary)
  |> should.be_true()
}
