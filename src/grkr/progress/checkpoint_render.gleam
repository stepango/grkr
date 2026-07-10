import gleam/option.{type Option, None, Some}
import grkr/progress/checkpoint_stage
import grkr/progress/checkpoint_id

pub type CheckpointContent {
  CheckpointContent(
    stage: checkpoint_stage.CheckpointStage,
    task_slug: String,
    body: String,
    pr_url: Option(String),
  )
}

pub fn render_checkpoint(content: CheckpointContent) -> String {
  let marker =
    checkpoint_id.marker(content.stage, content.task_slug)
    |> checkpoint_id.to_html_comment

  let header = checkpoint_stage.to_display_name(content.stage)
  let body_section = render_body(content.body)
  let pr_section = render_pr_link(content.pr_url)

  marker
    <> "\n\n## "
    <> header
    <> "\n\n"
    <> body_section
    <> pr_section
}

fn render_body(body: String) -> String {
  case body {
    "" -> ""
    _ -> body <> "\n\n"
  }
}

fn render_pr_link(pr_url: Option(String)) -> String {
  case pr_url {
    Some(url) -> {
      "### PR\n\n"
        <> "Created PR: "
        <> url
        <> "\n"
    }
    None -> ""
  }
}

pub fn render_pr_summary(
  task_slug: String,
  pr_url: String,
  branch_url: String,
) -> String {
  let marker =
    checkpoint_id.marker(checkpoint_stage.PrSummary, task_slug)
    |> checkpoint_id.to_html_comment

  marker
    <> "\n\n## PR summary\n\n"
    <> "Branch: "
    <> branch_url
    <> "\n\n"
    <> "PR: "
    <> pr_url
    <> "\n"
}

pub fn render_refusal(
  task_slug: String,
  reason_class: String,
  reasoning: String,
) -> String {
  let marker =
    checkpoint_id.marker(checkpoint_stage.Refusal, task_slug)
    |> checkpoint_id.to_html_comment

  let header = checkpoint_stage.to_display_name(checkpoint_stage.Refusal)

  marker
    <> "\n\n## "
    <> header
    <> "\n\n"
    <> "**Reason class:** "
    <> reason_class
    <> "\n\n"
    <> reasoning
    <> "\n"
}

pub fn extract_stage_from_comment(
  comment: String,
) -> Result(checkpoint_stage.CheckpointStage, String) {
  checkpoint_id.parse_marker_from_comment(comment)
}

pub fn has_checkpoint_marker(
  comment: String,
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> Bool {
  checkpoint_id.matches_marker(comment, stage, task_slug)
}
