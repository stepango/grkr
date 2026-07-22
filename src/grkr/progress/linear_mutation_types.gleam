//// linear_mutation_types.gleam
//// Shared public types for linear_mutation (LOC hygiene split).
//// Zero behavior change; moved from monolithic linear_mutation.gleam.
//// Constructors live here; facade re-exports type aliases for annotations.

pub type LinearIssueId {
  LinearIssueId(value: String)
}

pub type LinearTokenStatus {
  TokenAvailable
  TokenUnavailable
  TokenInvalid
}

pub type MutationRequest {
  MutationRequest(
    query: String,
    variables_json: String,
    idempotency_key: String,
  )
}

pub type MutationResult {
  MutationSuccess(comment_id: String)
  MutationStateUpdateSuccess
  MutationNeedsToken
  MutationFailed(error: String)
}
