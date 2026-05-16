import gleeunit
import gleeunit/should
import grkr/project_status/normalization

pub fn main() {
  gleeunit.main()
}

pub fn normalize_option_name_trims_test() {
  normalization.normalize_option_name("  Todo  ")
  |> should.equal("todo")
}

pub fn normalize_option_name_collapses_whitespace_test() {
  normalization.normalize_option_name("In   Progress")
  |> should.equal("in progress")
}

pub fn normalize_option_name_case_insensitive_test() {
  normalization.normalize_option_name("DONE")
  |> should.equal("done")

  normalization.normalize_option_name("In Progress")
  |> should.equal("in progress")
}

pub fn normalize_option_name_combined_test() {
  normalization.normalize_option_name("  In   Progress  ")
  |> should.equal("in progress")

  normalization.normalize_option_name("  Backlog  ")
  |> should.equal("backlog")
}

pub fn normalize_option_name_newlines_and_tabs_test() {
  normalization.normalize_option_name("In\nProgress")
  |> should.equal("in progress")

  normalization.normalize_option_name("In\t\tProgress")
  |> should.equal("in progress")
}

pub fn names_match_test() {
  normalization.names_match("Todo", "TODO")
  |> should.be_true()

  normalization.names_match("In Progress", "in progress")
  |> should.be_true()

  normalization.names_match("In Progress", "In   Progress")
  |> should.be_true()

  normalization.names_match("Done", "Backlog")
  |> should.be_false()
}

pub fn trim_and_collapse_test() {
  normalization.trim_and_collapse("  In   Progress  ")
  |> should.equal("In Progress")

  normalization.trim_and_collapse("Todo")
  |> should.equal("Todo")
}
