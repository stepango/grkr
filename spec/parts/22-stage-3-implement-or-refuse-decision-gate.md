## 19. Stage 3: implement-or-refuse decision gate

This is the new required decision stage.

After `research` and `plan`, the agent must decide whether to:

- proceed to implementation, or
- refuse implementation.

This decision must be made before any implementation attempt.

### 19.1 Decision authority

The decision is delegated to a separate Codex invocation with a tightly-scoped prompt using:

- issue description,
- relevant comments,
- `research.md`,
- `plan.md`,
- repository context,
- project policy.

### 19.2 Possible decisions

- `proceed`
- `refuse`

### 19.3 Default decision policy

The agent should **refuse** if any of the following hold:

1. **underspecified issue**
   - acceptance criteria are unclear
   - expected behavior is ambiguous
   - important implementation details are missing

2. **issue too large or high complexity**
   - task spans multiple systems
   - requires major design decisions
   - should be decomposed into smaller issues

3. **missing dependencies**
   - required upstream issue or PR is not implemented
   - required API or schema does not exist
   - external service or infra dependency is unavailable

4. **blocked by product or design decision**
   - user experience or product requirements are unresolved
   - conflicting approaches are possible and no choice is specified

5. **unsafe or inappropriate for autonomous implementation**
   - high-risk migration
   - irreversible data changes
   - security-sensitive or policy-sensitive changes needing human review

6. **repository state not suitable**
   - tests or build are fundamentally broken in a way unrelated to the issue
   - required branch context is missing

### 19.4 Proceed criteria

The agent should proceed only if:

- the issue is sufficiently specified,
- the implementation is bounded enough for one autonomous change,
- dependencies appear ready,
- risks are acceptable,
- a test strategy exists.

### 19.5 Implementation attempt cap

The agent must not loop forever on the same issue. If implementation repeatedly fails due to issue quality rather than transient execution problems, it may convert the workflow from `implement` to `refuse`.

---

