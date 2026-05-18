import gleam/int
import gleam/string

fn graphql_string(value: String) -> String {
  "\""
  <> {
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
    |> string.replace("\r", "\\r")
  }
  <> "\""
}

/// Build a GraphQL query for fetching projectV2 items under a user (owner).
/// Supports cursor-based pagination via the after param (Result for consistency
/// with issue_provider/query.gleam style).
pub fn build_user_project_items_query(
  owner: String,
  project_number: Int,
  after: Result(String, Nil),
) -> String {
  let cursor_clause = case after {
    Ok(cursor) -> ", after: " <> graphql_string(cursor)
    Error(Nil) -> ""
  }

  build_project_items_query("user", owner, project_number, cursor_clause)
}

/// Build a GraphQL query for fetching projectV2 items under an organization (owner).
pub fn build_org_project_items_query(
  owner: String,
  project_number: Int,
  after: Result(String, Nil),
) -> String {
  let cursor_clause = case after {
    Ok(cursor) -> ", after: " <> graphql_string(cursor)
    Error(Nil) -> ""
  }

  build_project_items_query("organization", owner, project_number, cursor_clause)
}

fn build_project_items_query(
  owner_type: String,
  login: String,
  project_number: Int,
  cursor_clause: String,
) -> String {
  "query {\n"
  <> "  "
  <> owner_type
  <> "(login: "
  <> graphql_string(login)
  <> ") {\n"
  <> "    projectV2(number: "
  <> int.to_string(project_number)
  <> ") {\n"
  <> "      items(first: 100"
  <> cursor_clause
  <> ") {\n"
  <> "        nodes {\n"
  <> "          id\n"
  <> "          fieldValues(first: 50) {\n"
  <> "            nodes {\n"
  <> "              ... on ProjectV2ItemFieldSingleSelectValue {\n"
  <> "                name\n"
  <> "                field {\n"
  <> "                  ... on ProjectV2FieldCommon {\n"
  <> "                    name\n"
  <> "                  }\n"
  <> "                }\n"
  <> "              }\n"
  <> "              ... on ProjectV2ItemFieldNumberValue {\n"
  <> "                number\n"
  <> "                field {\n"
  <> "                  ... on ProjectV2FieldCommon {\n"
  <> "                    name\n"
  <> "                  }\n"
  <> "                }\n"
  <> "              }\n"
  <> "            }\n"
  <> "          }\n"
  <> "          content {\n"
  <> "            __typename\n"
  <> "            ... on Issue {\n"
  <> "              number\n"
  <> "              title\n"
  <> "              updatedAt\n"
  <> "              state\n"
  <> "              repository {\n"
  <> "                nameWithOwner\n"
  <> "              }\n"
  <> "              assignees(first: 20) {\n"
  <> "                nodes {\n"
  <> "                  login\n"
  <> "                }\n"
  <> "              }\n"
  <> "            }\n"
  <> "          }\n"
  <> "        }\n"
  <> "        pageInfo {\n"
  <> "          hasNextPage\n"
  <> "          endCursor\n"
  <> "        }\n"
  <> "      }\n"
  <> "    }\n"
  <> "  }\n"
  <> "}"
}

/// Convenience: build user query with no cursor (first page)
pub fn build_user_project_items_query_first(
  owner: String,
  project_number: Int,
) -> String {
  build_user_project_items_query(owner, project_number, Error(Nil))
}

/// Convenience: build org query with no cursor (first page)
pub fn build_org_project_items_query_first(
  owner: String,
  project_number: Int,
) -> String {
  build_org_project_items_query(owner, project_number, Error(Nil))
}
