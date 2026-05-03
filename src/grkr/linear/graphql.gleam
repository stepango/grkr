import grkr/linear/types
import gleam/dict
import gleam/list
import gleam/string

pub fn viewer_query() -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "query Viewer { viewer { id name email } }",
    variables: dict.new(),
  )
}

pub fn projects_query() -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "query Projects { projects { nodes { id name url } } }",
    variables: dict.new(),
  )
}

pub fn teams_query() -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "query Teams { teams { nodes { id name key } } }",
    variables: dict.new(),
  )
}

pub fn issue_query(issue_id: String) -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "query Issue($id: String!) { issue(id: $id) { id title description url state { id } } }",
    variables: dict.from_list([#("id", issue_id)]),
  )
}

pub fn create_issue_mutation(
  team_id: String,
  title: String,
  description: String,
) -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "mutation CreateIssue($teamId: String!, $title: String!, $description: String!) { issueCreate(input: { teamId: $teamId, title: $title, description: $description }) { issue { id title description url state { id } } } }",
    variables: dict.from_list([
      #("teamId", team_id),
      #("title", title),
      #("description", description),
    ]),
  )
}

pub fn create_comment_mutation(
  issue_id: String,
  body: String,
) -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "mutation CreateComment($issueId: String!, $body: String!) { commentCreate(input: { issueId: $issueId, body: $body }) { comment { id body } } }",
    variables: dict.from_list([
      #("issueId", issue_id),
      #("body", body),
    ]),
  )
}

pub fn update_issue_state_mutation(
  issue_id: String,
  state_id: String,
) -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "mutation UpdateIssueState($issueId: String!, $stateId: String!) { issueUpdate(id: $issueId, input: { stateId: $stateId }) { issue { id title state { id } } } }",
    variables: dict.from_list([
      #("issueId", issue_id),
      #("stateId", state_id),
    ]),
  )
}

pub fn archive_issue_mutation(issue_id: String) -> types.GraphQLQuery {
  types.GraphQLQuery(
    query: "mutation ArchiveIssue($issueId: String!) { issueArchive(id: $issueId) { success } }",
    variables: dict.from_list([#("issueId", issue_id)]),
  )
}

pub fn format_query(query: types.GraphQLQuery) -> String {
  let vars =
    query.variables
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(key, value) = pair
      key <> ": " <> value
    })
    |> string.join(", ")

  "Query: " <> query.query <> "\nVariables: " <> vars
}

pub fn is_query_safe(query: types.GraphQLQuery) -> Bool {
  let query_lower = string.lowercase(query.query)

  query_lower
  |> string.contains("mutation")
  |> fn(is_mutation) {
    case is_mutation {
      True -> False
      False -> True
    }
  }
}
