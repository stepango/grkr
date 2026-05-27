import gleam/list

import gleeunit
import gleeunit/should

import grkr/github_picker/config
import grkr/github_picker/decoder
import grkr/github_picker/types.{
  type GitHubPickerConfig, NoPriority, Number, NumberValue,
  SingleSelect, SingleSelectValue,
}

pub fn main() {
  gleeunit.main()
}

fn base_cfg(mode: types.PriorityMode) -> GitHubPickerConfig {
  config.make_test_config(
    "stepango/grkr",
    "stepango",
    1,
    "Todo",
    mode,
    ["P0", "P1", "P2"],
    "bot",
  )
}

fn fixture_json(name: String) -> String {
  case name {
    "empty" -> "{\"items\": []}"
    "bad" -> "{not json"
    "single_select" ->
      "{\"data\":{\"user\":{\"projectV2\":{\"items\":{\"nodes\":[{\"id\":\"PVTI_1\",\"content\":{\"__typename\":\"Issue\",\"number\":1,\"title\":\"First top priority\",\"updatedAt\":\"2026-03-10T10:00:00Z\",\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"stepango/grkr\"},\"assignees\":{\"nodes\":[{\"login\":\"robot\"}]}},\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Status\"},\"name\":\"Todo\"},{\"field\":{\"name\":\"Priority\"},\"name\":\"P0\"}]}}]}}}}"
    "number" ->
      "{\"data\":{\"user\":{\"projectV2\":{\"items\":{\"nodes\":[{\"id\":\"PVTI_12\",\"content\":{\"__typename\":\"Issue\",\"number\":12,\"title\":\"Highest number priority\",\"updatedAt\":\"2026-03-11T10:00:00Z\",\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"stepango/grkr\"},\"assignees\":{\"nodes\":[{\"login\":\"robot\"}]}},\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Status\"},\"name\":\"Todo\"},{\"field\":{\"name\":\"Priority\"},\"number\":8}]}}]}}}}"
    "org_shape" ->
      "{\"data\":{\"organization\":{\"projectV2\":{\"items\":{\"nodes\":[{\"id\":\"PVTI_o1\",\"content\":{\"__typename\":\"Issue\",\"number\":77,\"title\":\"Org item\",\"updatedAt\":\"\",\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"r\"},\"assignees\":{\"nodes\":[]}},\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Status\"},\"name\":\"Todo\"},{\"field\":{\"name\":\"Priority\"},\"name\":\"P1\"}]}}]}}}}"
    "flat_items" ->
      "{\"items\":[{\"id\":\"p1\",\"content\":{\"number\":99,\"title\":\"min\",\"updatedAt\":\"\",\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"stepango/grkr\"},\"assignees\":{\"nodes\":[]}},\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Status\"},\"name\":\"Todo\"}]}}]}"
    "missing_fields" ->
      "{\"items\":[{\"id\":\"m1\",\"content\":{\"number\":42,\"title\":\"missing fields\",\"updatedAt\":\"2026\",\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"stepango/grkr\"},\"assignees\":{\"nodes\":[]}},\"fieldValues\":{\"nodes\":[]}}]}"
    _ -> "{}"
  }
}

pub fn decode_project_items_empty_test() {
  let cfg = base_cfg(SingleSelect)
  decoder.decode_project_items(fixture_json("empty"), cfg)
  |> should.equal(Ok([]))
}

pub fn decode_project_items_bad_json_test() {
  let cfg = base_cfg(SingleSelect)
  decoder.decode_project_items(fixture_json("bad"), cfg)
  |> should.be_error()
}

pub fn decode_project_items_single_select_test() {
  let cfg = base_cfg(SingleSelect)
  let assert Ok(items) = decoder.decode_project_items(fixture_json("single_select"), cfg)
  list.length(items) |> should.equal(1)
  let assert Ok(item) = list.first(items)
  item.content.number |> should.equal(1)
  item.priority |> should.equal(SingleSelectValue("P0"))
  item.status_name |> should.equal("Todo")
}

pub fn decode_project_items_number_priority_test() {
  let cfg = base_cfg(Number)
  let assert Ok(items) = decoder.decode_project_items(fixture_json("number"), cfg)
  list.length(items) |> should.equal(1)
  let assert Ok(item) = list.first(items)
  item.content.number |> should.equal(12)
  item.priority |> should.equal(NumberValue(8))
}

pub fn decode_project_items_org_shape_test() {
  let cfg = base_cfg(SingleSelect)
  let assert Ok(items) = decoder.decode_project_items(fixture_json("org_shape"), cfg)
  list.length(items) |> should.equal(1)
  let assert Ok(item) = list.first(items)
  item.content.number |> should.equal(77)
  item.priority |> should.equal(SingleSelectValue("P1"))
}

pub fn decode_project_items_flat_items_shape_test() {
  let cfg = base_cfg(SingleSelect)
  let assert Ok(items) = decoder.decode_project_items(fixture_json("flat_items"), cfg)
  list.length(items) |> should.equal(1)
  let assert Ok(item) = list.first(items)
  item.content.number |> should.equal(99)
  item.status_name |> should.equal("Todo")
  item.priority |> should.equal(NoPriority)
}

pub fn decode_handles_missing_fields_gracefully_test() {
  let cfg = base_cfg(SingleSelect)
  let assert Ok(items) = decoder.decode_project_items(fixture_json("missing_fields"), cfg)
  list.length(items) |> should.equal(1)
  let assert Ok(i) = list.first(items)
  i.content.number |> should.equal(42)
  i.status_name |> should.equal("")
  i.priority |> should.equal(NoPriority)
}

pub fn decode_project_items_live_shape_test() {
  let cfg = base_cfg(SingleSelect)
  let json = "{\"items\":[{\"id\":\"PVTI_live_15\",\"content\":{\"__typename\":\"Issue\",\"number\":15,\"title\":\"Actual project shape candidate\",\"updatedAt\":\"2026-03-08T10:00:00Z\",\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"stepango/grkr\"},\"assignees\":{\"nodes\":[{\"login\":\"robot\"}]}},\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Status\"},\"name\":\"Todo\"},{\"field\":{\"name\":\"Priority\"},\"name\":\"P1\"}]}}]}"
  let assert Ok(items) = decoder.decode_project_items(json, cfg)
  list.length(items) |> should.equal(1)
  let assert Ok(item) = list.first(items)
  item.content.number |> should.equal(15)
  item.priority |> should.equal(SingleSelectValue("P1"))
}
