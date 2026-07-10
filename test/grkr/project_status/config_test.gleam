import gleeunit
import gleeunit/should
import grkr/project_status/config
import grkr/project_status/types.{Backlog, Custom, Done, InProgress, Todo}

pub fn main() {
  gleeunit.main()
}

pub fn parse_updates_enabled_test() {
  config.parse_updates_enabled("true")
  |> should.be_true()
  config.parse_updates_enabled("1")
  |> should.be_true()
  config.parse_updates_enabled("yes")
  |> should.be_true()
  config.parse_updates_enabled("")
  |> should.be_true()
  config.parse_updates_enabled("false")
  |> should.be_false()
  config.parse_updates_enabled("False")
  |> should.be_false()
  config.parse_updates_enabled("0")
  |> should.be_false()
  config.parse_updates_enabled("no")
  |> should.be_false()
}

pub fn parse_updates_enabled_whitespace_test() {
  config.parse_updates_enabled("  true  ")
  |> should.be_true()
  config.parse_updates_enabled("  false  ")
  |> should.be_false()
}

pub fn target_status_value_test() {
  config.target_status_value(Todo, "Todo", "In Progress", "Done", "Backlog")
  |> should.equal("Todo")
  config.target_status_value(
    InProgress,
    "Todo",
    "In Progress",
    "Done",
    "Backlog",
  )
  |> should.equal("In Progress")
  config.target_status_value(Done, "Todo", "In Progress", "Done", "Backlog")
  |> should.equal("Done")
  config.target_status_value(Backlog, "Todo", "In Progress", "Done", "Backlog")
  |> should.equal("Backlog")
  config.target_status_value(
    Custom("CustomStatus"),
    "Todo",
    "In Progress",
    "Done",
    "Backlog",
  )
  |> should.equal("CustomStatus")
}
