import gleam/option
import gleeunit
import gleeunit/should
import grkr/project_status/extraction

pub fn main() {
  gleeunit.main()
}

pub fn extract_item_id_from_issue_json_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"Todo\"}}]}"

  let result = extraction.extract_item_id(issue_json, option.Some(1))

  result
  |> should.equal(option.Some("PVTI_123"))
}

pub fn extract_item_id_no_matching_project_falls_back_to_first_item_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":2},\"status\":{\"name\":\"Todo\"}}]}"

  let result = extraction.extract_item_id(issue_json, option.Some(1))

  result
  |> should.equal(option.Some("PVTI_123"))
}

pub fn extract_item_id_fallback_any_project_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"status\":{\"name\":\"Todo\"}}]}"

  let result = extraction.extract_item_id(issue_json, option.None)

  result
  |> should.equal(option.Some("PVTI_123"))
}

pub fn extract_status_name_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"Todo\"}}]}"

  let result = extraction.extract_status_name(issue_json, option.Some(1))

  result
  |> should.equal(option.Some("Todo"))
}

pub fn extract_status_name_no_project_items_test() {
  let issue_json = "{\"projectItems\":[]}"

  let result = extraction.extract_status_name(issue_json, option.Some(1))

  result
  |> should.equal(option.None)
}

pub fn extract_project_metadata_test() {
  let project_json = "{\"id\":\"PROJ_1\",\"number\":1,\"owner\":\"stepango\"}"

  let result = extraction.extract_project_metadata(project_json)

  result
  |> should.be_ok()

  let assert Ok(metadata) = result
  metadata.id
  |> should.equal("PROJ_1")

  metadata.number
  |> should.equal(1)
}

pub fn extract_issue_number_test() {
  let issue_json = "{\"number\":42,\"title\":\"Test issue\"}"

  let result = extraction.extract_issue_number(issue_json)

  result
  |> should.equal(Ok(42))
}

pub fn find_item_id_by_issue_number_test() {
  let items_json =
    "{\"items\":[{\"id\":\"PVTI_456\",\"content\":{\"number\":42}}]}"

  let result = extraction.find_item_id_by_issue_number(items_json, 42)

  result
  |> should.equal(option.Some("PVTI_456"))
}

pub fn find_item_id_by_issue_number_not_found_test() {
  let items_json =
    "{\"items\":[{\"id\":\"PVTI_456\",\"content\":{\"number\":99}}]}"

  let result = extraction.find_item_id_by_issue_number(items_json, 42)

  result
  |> should.equal(option.None)
}

pub fn extract_item_id_with_string_project_number_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":\"1\"},\"status\":{\"name\":\"Todo\"}}]}"

  let result = extraction.extract_item_id(issue_json, option.Some(1))

  result
  |> should.equal(option.Some("PVTI_123"))
}
