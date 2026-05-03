import gleam/string
import gleam/int
import grkr/progress/checkpoint_stage

pub type CheckpointMarker {
  CheckpointMarker(
    stage: checkpoint_stage.CheckpointStage,
    task_slug: String,
    version: Int,
  )
}

pub fn marker(
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> CheckpointMarker {
  CheckpointMarker(stage: stage, task_slug: task_slug, version: 1)
}

pub fn marker_with_version(
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
  version: Int,
) -> CheckpointMarker {
  CheckpointMarker(stage: stage, task_slug: task_slug, version: version)
}

pub fn to_html_comment(marker: CheckpointMarker) -> String {
  "<!-- grkr:checkpoint stage="
    <> checkpoint_stage.to_string(marker.stage)
    <> " task="
    <> marker.task_slug
    <> " version="
    <> int.to_string(marker.version)
    <> " -->"
}

pub fn to_idempotency_key(marker: CheckpointMarker) -> String {
  "grkr-checkpoint-"
    <> checkpoint_stage.to_string(marker.stage)
    <> "-"
    <> marker.task_slug
}

pub fn parse_marker_from_comment(
  comment: String,
) -> Result(checkpoint_stage.CheckpointStage, String) {
  case string.split(comment, "stage=") {
    [_, rest] -> {
      case string.split(rest, " ") {
        [stage_part, ..] -> checkpoint_stage.from_string(stage_part)
        _ -> Error("Could not parse marker format")
      }
    }
    _ -> Error("Could not find stage in marker")
  }
}

pub fn matches_marker(
  comment: String,
  expected_stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> Bool {
  let expected_marker = to_html_comment(marker(expected_stage, task_slug))
  string.contains(comment, expected_marker)
}

pub fn extract_task_slug(marker: CheckpointMarker) -> String {
  marker.task_slug
}

pub fn extract_stage(marker: CheckpointMarker) -> checkpoint_stage.CheckpointStage {
  marker.stage
}
