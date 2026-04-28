import gleam/int
import grkr/issue_provider/types

/// Build a GraphQL query for fetching assigned issues
pub fn build_assigned_issues_query(
  first: Int,
  after: Result(String, Nil),
  filter: Result(types.IssueFilter, Nil),
) -> String {
  let pagination_clause = case after {
    Ok(cursor) -> ", after: \"" <> cursor <> "\""
    Error(Nil) -> ""
  }

  let filter_clause = case filter {
    Ok(f) -> {
      let state_filter = ", state: { name: { eq: \"" <> f.state_name <> "\" } }"

      let project_filter = case f.project_id {
        Ok(pid) -> ", project: { id: { eq: \"" <> pid <> "\" } }"
        Error(Nil) -> ""
      }

      let team_filter = case f.team_id {
        Ok(tid) -> ", team: { id: { eq: \"" <> tid <> "\" } }"
        Error(Nil) -> ""
      }

      "filter: { assignee: { me: true } " <> state_filter <> project_filter
        <> team_filter
        <> " }"
    }
    Error(Nil) -> "filter: { assignee: { me: true } }"
  }

  "query {
  viewer {
    assignedIssues(first: "
    <> int.to_string(first)
    <> pagination_clause
    <> "
    "
    <> filter_clause
    <> ") {
      nodes {
        id
        identifier
        title
        description
        url
        state {
          id
          name
          type
        }
        priority
        assignee {
          id
          name
          displayName
        }
        project {
          id
          name
          url
        }
        team {
          id
          key
          name
        }
        createdAt
        updatedAt
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}"
}

/// Build a GraphQL query for fetching teams
pub fn build_teams_query() -> String {
  "query {
  viewer {
    teams {
      nodes {
        id
        key
        name
      }
    }
  }
}"
}

/// Build a GraphQL query for fetching team projects
pub fn build_team_projects_query(team_id: String) -> String {
  "query {
  team(id: \"" <> team_id <> "\") {
    projects {
      nodes {
        id
        name
        url
      }
    }
  }
}"
}

/// Build a GraphQL query for fetching a single issue by identifier
pub fn build_issue_query(identifier: String) -> String {
  "query {
  issue(identifier: \"" <> identifier <> "\") {
    id
    identifier
    title
    description
    url
    state {
      id
      name
      type
    }
    priority
    assignee {
      id
      name
      displayName
    }
    project {
      id
      name
      url
    }
    team {
      id
      key
      name
    }
    createdAt
    updatedAt
  }
}"
}

/// Build a GraphQL query for fetching viewer info
pub fn build_viewer_query() -> String {
  "query {
  viewer {
    id
    name
    displayName
    email
  }
}"
}

/// Query configuration
pub type QueryConfig {
  QueryConfig(
    first: Int,
    after: Result(String, Nil),
    filter: Result(types.IssueFilter, Nil),
  )
}

/// Create a default query config
pub fn default_query_config() -> QueryConfig {
  QueryConfig(first: 50, after: Error(Nil), filter: Error(Nil))
}

/// Create a query config with a filter
pub fn filtered_query_config(filter: types.IssueFilter) -> QueryConfig {
  QueryConfig(first: 50, after: Error(Nil), filter: Ok(filter))
}

/// Create a query config with pagination
pub fn paginated_query_config(
  first: Int,
  after: String,
) -> QueryConfig {
  QueryConfig(first: first, after: Ok(after), filter: Error(Nil))
}

/// Build query from config
pub fn build_query_from_config(config: QueryConfig) -> String {
  build_assigned_issues_query(config.first, config.after, config.filter)
}
