import gleeunit
import gleeunit/should
import grkr/progress/checkpoint_stage
import grkr/progress/linear_state

pub fn main() {
  gleeunit.main()
}

pub fn default_state_mapping_test() {
  let mapping = linear_state.default_state_mapping()

  mapping.research
  |> should.equal("In Progress")

  mapping.plan
  |> should.equal("In Progress")

  mapping.implementation
  |> should.equal("In Progress")

  mapping.test_state
  |> should.equal("In Review")

  mapping.done
  |> should.equal("Done")

  mapping.backlog
  |> should.equal("Backlog")
}

pub fn from_env_test() {
  let mock_env = fn(key) {
    case key {
      "LINEAR_STATE_RESEARCH" -> "Researching"
      "LINEAR_STATE_PLAN" -> "Planning"
      "LINEAR_STATE_IMPLEMENTATION" -> "Coding"
      "LINEAR_STATE_TEST" -> "Testing"
      "LINEAR_STATE_DONE" -> "Complete"
      "LINEAR_STATE_BACKLOG" -> "Icebox"
      _ -> ""
    }
  }

  let mapping = linear_state.from_env(mock_env)

  mapping.research
  |> should.equal("Researching")

  mapping.plan
  |> should.equal("Planning")

  mapping.implementation
  |> should.equal("Coding")

  mapping.test_state
  |> should.equal("Testing")

  mapping.done
  |> should.equal("Complete")

  mapping.backlog
  |> should.equal("Icebox")
}

pub fn from_env_fallback_test() {
  let mock_env = fn(_key) { "" }
  let mapping = linear_state.from_env(mock_env)

  mapping.research
  |> should.equal("In Progress")
}

pub fn state_for_stage_test() {
  let mapping = linear_state.default_state_mapping()

  linear_state.state_for_stage(mapping, checkpoint_stage.Research)
  |> should.equal("In Progress")

  linear_state.state_for_stage(mapping, checkpoint_stage.Plan)
  |> should.equal("In Progress")

  linear_state.state_for_stage(mapping, checkpoint_stage.Implementation)
  |> should.equal("In Progress")

  linear_state.state_for_stage(mapping, checkpoint_stage.Test)
  |> should.equal("In Review")

  linear_state.state_for_stage(mapping, checkpoint_stage.PrSummary)
  |> should.equal("Done")

  linear_state.state_for_stage(mapping, checkpoint_stage.Refusal)
  |> should.equal("Backlog")
}

pub fn normalize_state_name_test() {
  linear_state.normalize_state_name("  In Progress  ")
  |> should.equal("in progress")

  linear_state.normalize_state_name("DONE")
  |> should.equal("done")
}

pub fn states_match_test() {
  linear_state.states_match("In Progress", "in progress")
  |> should.be_true()

  linear_state.states_match("Done", "DONE")
  |> should.be_true()

  linear_state.states_match("In Progress", "Done")
  |> should.be_false()
}

pub fn is_terminal_state_test() {
  let mapping = linear_state.default_state_mapping()

  linear_state.is_terminal_state("Done", mapping)
  |> should.be_true()

  linear_state.is_terminal_state("done", mapping)
  |> should.be_true()

  linear_state.is_terminal_state("In Progress", mapping)
  |> should.be_false()
}
