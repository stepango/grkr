import gleam/int

/// Supported priority field modes in GitHub Projects
pub type PriorityMode {
  Number
  SingleSelect
}

/// GitHub Projects V2 picker configuration loaded from env + .grkr files
pub type GitHubPickerConfig {
  GitHubPickerConfig(
    repo: String,
    project_owner: String,
    project_number: Int,
    status_field_name: String,
    todo_value: String,
    priority_field_name: String,
    priority_mode: PriorityMode,
    priority_order: List(String),
    active_jobs: List(String),
    grkr_root: String,
    bot_login: String,
  )
}

/// Parsed value for a priority field on an item
pub type PriorityValue {
  NumberValue(Int)
  SingleSelectValue(String)
  NoPriority
}

/// Core issue fields extracted from GraphQL content
pub type IssueContent {
  IssueContent(
    number: Int,
    title: String,
    updated_at: String,
    state: String,
    repository: String,
    assignee_logins: List(String),
  )
}

/// A project item (Issue) with its Status and Priority field values
pub type ProjectItem {
  ProjectItem(
    project_item_id: String,
    content: IssueContent,
    status_name: String,
    priority: PriorityValue,
  )
}

/// Internal candidate with computed sort key for selection
pub type Candidate {
  Candidate(item: ProjectItem, priority_sort: Int)
}

/// The final selected issue ready for shell emit (includes computed job_key and task_slug)
pub type SelectedGitHubIssue {
  SelectedGitHubIssue(
    project_item_id: String,
    issue_number: Int,
    issue_title: String,
    issue_updated_at: String,
    priority_name: String,
    priority_number: String,
    job_key: String,
    task_slug: String,
  )
}

/// Errors when loading GitHub picker config from env
pub type ConfigError {
  MissingRequired(field: String)
  InvalidProjectNumber(value: String)
  InvalidPriorityMode(value: String)
  ActiveJobsUnreadable(path: String)
}

/// Errors from the selection logic
pub type SelectionError {
  NoMatchingIssue
}

/// Top level errors for the github_picker provider
pub type ProviderError {
  Config(ConfigError)
  Query(reason: String)
  Decode(reason: String)
  Selection(SelectionError)
}

/// Human readable error for ProviderError (used in ERROR= emit)
pub fn provider_error_to_string(e: ProviderError) -> String {
  case e {
    Config(ce) -> config_error_to_string(ce)
    Query(r) -> "GitHub query failed: " <> r
    Decode(r) -> "GitHub decode failed: " <> r
    Selection(_) -> "No matching Todo issue found in project"
  }
}

fn config_error_to_string(e: ConfigError) -> String {
  case e {
    MissingRequired(f) -> "Missing required config value: " <> f
    InvalidProjectNumber(v) -> "Invalid PROJECT_NUMBER: " <> v
    InvalidPriorityMode(v) -> "Invalid PRIORITY_MODE: " <> v
    ActiveJobsUnreadable(p) -> "Could not read active jobs file: " <> p
  }
}

/// Build the JOB_KEY in the exact format expected by shell (issue:NNN:execution)
pub fn job_key_for_issue(issue_number: Int) -> String {
  "issue:" <> int.to_string(issue_number) <> ":execution"
}

/// Construct Selected from a ProjectItem + priority strings + slug fn
/// (task_slug import happens at use site or here; we expose helper)
pub fn selected_from_item(
  item: ProjectItem,
  priority_name: String,
  priority_number: String,
  task_slug: String,
) -> SelectedGitHubIssue {
  let issue_number = item.content.number
  SelectedGitHubIssue(
    project_item_id: item.project_item_id,
    issue_number: issue_number,
    issue_title: item.content.title,
    issue_updated_at: item.content.updated_at,
    priority_name: priority_name,
    priority_number: priority_number,
    job_key: job_key_for_issue(issue_number),
    task_slug: task_slug,
  )
}
