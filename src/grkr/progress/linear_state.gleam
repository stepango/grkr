import gleam/string
import gleam/dict
import grkr/progress/checkpoint_stage

pub type LinearStateMapping {
  LinearStateMapping(
    research: String,
    plan: String,
    implementation: String,
    test_state: String,
    done: String,
    backlog: String,
  )
}

pub type LinearStateType {
  StateTypeInProgress
  StateTypeDone
  StateTypeBacklog
  StateTypeCanceled
}

pub fn default_state_mapping() -> LinearStateMapping {
  LinearStateMapping(
    research: "In Progress",
    plan: "In Progress",
    implementation: "In Progress",
    test_state: "In Review",
    done: "Done",
    backlog: "Backlog",
  )
}

pub fn from_env(env_getter: fn(String) -> String) -> LinearStateMapping {
  let defaults = default_state_mapping()
  let research = default_or_fallback(env_getter("LINEAR_STATE_RESEARCH"), defaults.research)
  let plan = default_or_fallback(env_getter("LINEAR_STATE_PLAN"), defaults.plan)
  let implementation = default_or_fallback(env_getter("LINEAR_STATE_IMPLEMENTATION"), defaults.implementation)
  let test_state = default_or_fallback(env_getter("LINEAR_STATE_TEST"), defaults.test_state)
  let done = default_or_fallback(env_getter("LINEAR_STATE_DONE"), defaults.done)
  let backlog = default_or_fallback(env_getter("LINEAR_STATE_BACKLOG"), defaults.backlog)

  LinearStateMapping(
    research: research,
    plan: plan,
    implementation: implementation,
    test_state: test_state,
    done: done,
    backlog: backlog,
  )
}

fn default_or_fallback(value: String, fallback: String) -> String {
  case string.trim(value) {
    "" -> fallback
    v -> v
  }
}

pub fn state_for_stage(
  mapping: LinearStateMapping,
  stage: checkpoint_stage.CheckpointStage,
) -> String {
  case stage {
    checkpoint_stage.Research -> mapping.research
    checkpoint_stage.Plan -> mapping.plan
    checkpoint_stage.Implementation -> mapping.implementation
    checkpoint_stage.Test -> mapping.test_state
    checkpoint_stage.PrSummary -> mapping.done
    checkpoint_stage.Refusal -> mapping.backlog
  }
}

pub fn state_type_for_stage(
  stage: checkpoint_stage.CheckpointStage,
) -> LinearStateType {
  case stage {
    checkpoint_stage.Research -> StateTypeInProgress
    checkpoint_stage.Plan -> StateTypeInProgress
    checkpoint_stage.Implementation -> StateTypeInProgress
    checkpoint_stage.Test -> StateTypeInProgress
    checkpoint_stage.PrSummary -> StateTypeDone
    checkpoint_stage.Refusal -> StateTypeBacklog
  }
}

pub fn normalize_state_name(state: String) -> String {
  state
  |> string.trim()
  |> string.lowercase()
}

pub fn states_match(a: String, b: String) -> Bool {
  normalize_state_name(a) == normalize_state_name(b)
}

pub fn to_dict(mapping: LinearStateMapping) -> dict.Dict(String, String) {
  dict.from_list([
    #("research", mapping.research),
    #("plan", mapping.plan),
    #("implementation", mapping.implementation),
    #("test", mapping.test_state),
    #("done", mapping.done),
    #("backlog", mapping.backlog),
  ])
}

pub fn is_terminal_state(state: String, mapping: LinearStateMapping) -> Bool {
  let normalized = normalize_state_name(state)
  let done_normalized = normalize_state_name(mapping.done)
  normalized == done_normalized
}
