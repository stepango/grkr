//// validate.gleam
//// Thin public facade (LOC hygiene split, t_74a7a161).
//// Stable module: grkr/doctor/validate
//// Delegates to validate_{tools,agent,config,run}. Zero intentional behavior change.
//// doctor/cli.gleam is the sole caller (run_validate / run_create_config).

import grkr/doctor/validate_agent as agent
import grkr/doctor/validate_config as config
import grkr/doctor/validate_run as run_mod
import grkr/doctor/validate_tools as tools

// --- config / paths ---
pub fn grkr_root() -> String {
  config.grkr_root()
}

pub fn config_file_path() -> String {
  config.config_file_path()
}

// --- tools + gh auth ---
pub fn validate_tools() -> Bool {
  tools.validate_tools()
}

pub fn validate_gh_auth() -> Bool {
  tools.validate_gh_auth()
}

// --- coding agent ---
pub fn validate_codex() -> Bool {
  agent.validate_codex()
}

pub fn validate_grok() -> Bool {
  agent.validate_grok()
}

pub fn coding_agent_name() -> String {
  agent.coding_agent_name()
}

pub fn validate_coding_agent() -> Bool {
  agent.validate_coding_agent()
}

// --- config + remote + grkr-dir ---
pub fn validate_config_file() -> Bool {
  config.validate_config_file()
}

pub fn validate_repo_remote() -> Bool {
  config.validate_repo_remote()
}

pub fn validate_grkr_dir() -> Bool {
  config.validate_grkr_dir()
}

// --- orchestrator ---
pub fn run_validate() -> Int {
  run_mod.run_validate()
}

pub fn run_create_config(project_number: String) -> Int {
  run_mod.run_create_config(project_number)
}
