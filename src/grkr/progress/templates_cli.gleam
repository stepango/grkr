//// templates_cli.gleam
//// Cluster C extracted from progress/main.gleam for LOC hygiene (t_8c7cd0a0).
//// Thin CLI wrappers around pure templates (research/plan/decision/issue prompts, pr bodies, footers, select, ensure, completion).
/// These are the 8+ render fns called by bin/grkr-templates.sh and progress/cli.
/// Delegates to templates.gleam. Public surface preserved via thin facade in main.gleam.
/// Zero behavior change; template strings identical.

import grkr/progress/templates

pub fn cli_render_research_checkpoint(
  issue: String,
  title: String,
  body: String,
  url: String,
  task_slug: String,
) -> String {
  templates.render_research_checkpoint(issue, title, body, url, task_slug)
}

pub fn cli_render_plan_checkpoint(
  issue: String,
  title: String,
  task_slug: String,
) -> String {
  templates.render_plan_checkpoint(issue, title, task_slug)
}

pub fn cli_render_decision_prompt(
  issue: String,
  title: String,
  url: String,
  body: String,
  task_slug: String,
  worktree_dir: String,
  grkr_root: String,
  max_file_lines: String,
) -> String {
  templates.render_decision_prompt(
    issue,
    title,
    url,
    body,
    task_slug,
    worktree_dir,
    grkr_root,
    max_file_lines,
  )
}

pub fn cli_render_issue_prompt(
  issue: String,
  title: String,
  url: String,
  body: String,
  task_slug: String,
  worktree_dir: String,
  grkr_root: String,
  max_file_lines: String,
) -> String {
  templates.render_issue_prompt(
    issue,
    title,
    url,
    body,
    task_slug,
    worktree_dir,
    grkr_root,
    max_file_lines,
  )
}

pub fn cli_render_line_limit_fix_prompt(
  issue: String,
  title: String,
  task_slug: String,
  violations: String,
  max_file_lines: String,
) -> String {
  templates.render_line_limit_fix_prompt(
    issue,
    title,
    task_slug,
    violations,
    max_file_lines,
  )
}

pub fn cli_render_default_pr_body(body: String, title: String) -> String {
  templates.render_default_pr_body(body, title)
}

pub fn cli_render_compact_pr_body(short_body: String, short_title: String) -> String {
  templates.render_compact_pr_body(short_body, short_title)
}

pub fn cli_render_issue_footer(issue: String) -> String {
  templates.render_issue_footer(issue)
}

pub fn cli_select_codex_pr_section(content: String) -> String {
  templates.select_codex_heading_section(content)
}

pub fn cli_ensure_github_pr_body(
  content: String,
  issue_body: String,
  title: String,
  issue: String,
  max_chars: Int,
) -> String {
  templates.ensure_github_pr_body(content, issue_body, title, issue, max_chars)
}

pub fn cli_render_github_completion_summary(
  issue: String,
  title: String,
  branch_url: String,
  pr_url: String,
) -> String {
  templates.render_github_completion_summary(issue, title, branch_url, pr_url)
}
