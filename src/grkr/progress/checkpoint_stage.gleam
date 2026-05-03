import gleam/string
import gleam/list

pub type CheckpointStage {
  Research
  Plan
  Refusal
  Implementation
  Test
  PrSummary
}

pub fn from_string(stage: String) -> Result(CheckpointStage, String) {
  case string.lowercase(stage) {
    "research" -> Ok(Research)
    "plan" -> Ok(Plan)
    "refusal" -> Ok(Refusal)
    "implementation" -> Ok(Implementation)
    "test" -> Ok(Test)
    "pr_summary" -> Ok(PrSummary)
    _ -> Error("Invalid checkpoint stage: " <> stage)
  }
}

pub fn to_string(stage: CheckpointStage) -> String {
  case stage {
    Research -> "research"
    Plan -> "plan"
    Refusal -> "refusal"
    Implementation -> "implementation"
    Test -> "test"
    PrSummary -> "pr_summary"
  }
}

pub fn to_display_name(stage: CheckpointStage) -> String {
  case stage {
    Research -> "Research checkpoint"
    Plan -> "Plan checkpoint"
    Refusal -> "Implementation refused"
    Implementation -> "Implementation checkpoint"
    Test -> "Test checkpoint"
    PrSummary -> "PR summary"
  }
}

pub fn all_stages() -> List(CheckpointStage) {
  [Research, Plan, Refusal, Implementation, Test, PrSummary]
}

pub fn is_valid_stage(stage: String) -> Bool {
  case from_string(stage) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn requires_linear_state_update(stage: CheckpointStage) -> Bool {
  list.any([Research, Plan, Implementation, Test, PrSummary], fn(s) { s == stage })
}

pub fn terminal_stage() -> CheckpointStage {
  PrSummary
}
