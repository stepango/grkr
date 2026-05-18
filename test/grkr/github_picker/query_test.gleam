import gleam/string

import gleeunit
import gleeunit/should

import grkr/github_picker/query

pub fn main() {
  gleeunit.main()
}

pub fn build_user_project_items_query_first_test() {
  let q =
    query.build_user_project_items_query_first("stepango", 7)

  contains(q, "query {") |> should.be_true()
  contains(q, "user(login: \"stepango\")") |> should.be_true()
  contains(q, "projectV2(number: 7)") |> should.be_true()
  contains(q, "items(first: 100)") |> should.be_true()
  contains(q, "__typename") |> should.be_true()
  contains(q, "... on Issue {") |> should.be_true()
  contains(q, "number") |> should.be_true()
  contains(q, "title") |> should.be_true()
  contains(q, "ProjectV2ItemFieldSingleSelectValue") |> should.be_true()
  contains(q, "ProjectV2ItemFieldNumberValue") |> should.be_true()
  contains(q, "pageInfo {") |> should.be_true()
  contains(q, "hasNextPage") |> should.be_true()
  contains(q, "endCursor") |> should.be_true()
  // no after clause
  contains(q, "after:") |> should.be_false()
}

pub fn build_user_project_items_query_with_cursor_test() {
  let q =
    query.build_user_project_items_query("stepango", 7, Ok("Y3Vyc29yX2V4YW1wbGU="))

  contains(q, "after: \"Y3Vyc29yX2V4YW1wbGU=\"") |> should.be_true()
  contains(q, "items(first: 100, after:") |> should.be_true()
}

pub fn build_org_project_items_query_first_test() {
  let q =
    query.build_org_project_items_query_first("acme", 42)

  contains(q, "organization(login: \"acme\")") |> should.be_true()
  contains(q, "projectV2(number: 42)") |> should.be_true()
}

fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
