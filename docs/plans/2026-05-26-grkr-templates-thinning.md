# grkr-templates.sh Thinning Implementation Plan (t_23a1c5ae)

> **For Hermes:** Use systematic approach + edits with patch/write_file + verification. Follow AGENTS.md strictly: update README after functional, <=1000 LOC, spec/parts canonical (no change expected), run sync-spec, preserve bin/ shell, small explicit. GitHub-only v2.

**Goal:** Thin legacy 317 LOC grkr-templates.sh (10274B) to thin ~60 LOC wrapper delegating to Gleam for all template rendering. Preserve exact function contracts, outputs, behavior for bin/grkr + 10+ tests. Add minimal Gleam support in progress/ (extend existing for no new top level module). Update docs + README + run sync-spec + tests green + build clean.

**Architecture:** 
- Port 8 write_* generators + summarize_text + reuse checkpoint_marker to pure Gleam string builders in new src/grkr/progress/templates.gleam (small file).
- Extend progress/main.gleam with cli_ render fns (delegating to templates).
- Extend progress/cli.gleam with new subcommands (e.g. render-research-checkpoint ...) that print to stdout.
- Thin bin/grkr-templates.sh : shebang, doctor, config, _grkr_templates helper (like gleam_wf), 8 thin fns that invoke CLI and redirect stdout to $file for writes, or call for others.
- Fallback behavior in CLI for no gleam.toml (echo error).
- Exact parity: outputs must match original sh heredocs byte-for-byte for same inputs (test via diff in verification).
- No change to call sites in bin/grkr or tests.

**Tech Stack:** Gleam  (string concat, result for errors), bash (thin wrappers), existing progress checkpoint_id/render.

**Constraints:**
- Keep all files <1000 LOC (progress/main will ~+100 = ~330 ok).
- Small explicit changes.
- After any func change: update README.md
- Run `bash scripts/sync-spec.sh` at end (expect noop).
- Backup original as bin/grkr-templates.sh.legacy-v1
- Green: gleam build, relevant grkr-*.sh tests that exercise templates (line-limit, pr-body, checkpoint-resume, refusal, smoke, etc), bash -n on sh, full npm test if time.
- Trace to this task + parent t_382618fa in docs.

**References (must read before edits):**
- AGENTS.md
- spec/parts/08-worker-scripts.md
- spec/parts/39-recommended-implementation-order.md
- spec/parts/17-issue-workflow-overview.md + 19,20,22,28,29 etc for contract
- docs/gleam-migration.md (current state)
- README.md (how it works, current status)
- bin/grkr (all call sites + summarize + ensure_ fns)
- Current bin/grkr-templates.sh (exact strings)
- Existing thins: bin/grkr-project-status.sh, bin/grkr-issue-workflow.sh, bin/grkr-task-slug.sh, bin/robot-main.sh (patterns)
- src/grkr/progress/{main,cli,checkpoint_render,checkpoint_id}.gleam (reuse marker)
- test/grkr-*.sh that cp the templates (no behavior change)

---

### Task 1: Backup + initial hygiene

**Objective:** Preserve original for safety, update todo/audit notes.

**Files:**
- Modify: docs/plans/2026-05-26-grkr-templates-thinning.md (this)
- Create: bin/grkr-templates.sh.legacy-v1 (copy of current)

**Steps:**
1. Run: cp bin/grkr-templates.sh bin/grkr-templates.sh.legacy-v1
2. Verify: ls -l bin/grkr-templates.sh*
3. Append note to .grkr/audit-grkr-issue-workflow-thinning.md or create small audit note if needed (small).
4. Update todo list in agent if active.

**Verification:**
- diff bin/grkr-templates.sh bin/grkr-templates.sh.legacy-v1 | head -5  (empty)
- wc -l bin/grkr-templates.sh.legacy-v1 == 317

**Commit:** git add ... ; git commit -m "backup: grkr-templates.sh.legacy-v1 pre-thinning (t_23a1c5ae)"

---

### Task 2: Add Gleam templates render module (new file)

**Objective:** Pure Gleam functions that produce exact same output strings as the 8 sh fns, using Gleam string building + reuse checkpoint marker.

**Files:**
- Create: src/grkr/progress/templates.gleam

**Step 1: Write the module skeleton + imports + summarize fn (port exact logic)**

```gleam
import gleam/string
import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_stage  // if needed, or reuse from render

pub fn summarize_text(text: String, max_chars: Int) -> String {
  // port the tr/sed/awk logic exactly
  let collapsed = text
    |> string.replace("\n", " ")
    |> string.replace("  ", " ")  // simplistic, improve to match sh regex
    // full port needed for exact: use regex if available or manual
  ...
}

pub fn render_research_checkpoint(issue: String, title: String, body: String, url: String, task_slug: String) -> String {
  let marker = checkpoint_id.marker(checkpoint_stage.Research, task_slug)  // may need add Research variant? wait reuse string or extend
  // build the exact heredoc content using <> concat or string.concat
  // include the $(checkpoint_marker ...) by calling format or hardcode call
  ...
}
```

Note: checkpoint_stage may need extension for "research", "plan" if not there (check).

**Step 2: Port all 8 render fns + helpers (write_ become render_ returning String)**

- render_research_checkpoint_file_content(issue, title, body, url, task_slug) -> String
- render_plan...
- render_decision_prompt...
- render_issue_prompt...
- render_line_limit_fix_prompt(issue, title, task_slug, violations)
- render_default_pr_body(body, title)
- render_compact_pr_body(body, title)  // uses summarize
- render_issue_footer(issue) for append

Make private fns if needed for shared.

Use """ multiline strings for the templates where possible, interpolate with <>

**Step 3: Add tests?** (minimal, since integration heavy; or unit for summarize + one render)

**Verification (after write):**
- gleam build (in project root)
- gleam test (if added test)

**Commit after pass.**

---

### Task 3: Wire CLI support in progress/

**Objective:** Expose the renders via progress/cli so shell can invoke without file write side effects in Gleam.

**Files:**
- Modify: src/grkr/progress/main.gleam (add cli_render_* fns + plan_* helpers)
- Modify: src/grkr/progress/cli.gleam (add case arms for new subcmds, usage help, ffi if needed)

**Step 1: In main.gleam add:**

pub fn cli_render_research_checkpoint(issue: String, title: String, body: String, url: String, task_slug: String) -> String {
  templates.render_research... 
}

Similar for others. For ones that write file, the cli just returns the string (shell redirects).

For append, perhaps separate or handle in sh.

**Step 2: In cli.gleam , extend the case "argv() " :**

Add:

["render-research-checkpoint", issue, title, body, url, slug] -> io.print( main.cli_render_research_checkpoint(...) )

Similar for 7 others.

Update usage text with new commands.

Handle errors gracefully like others.

**Step 3: Add any needed ffi if argv changes (no).**

**Verification:**
- After edit: cd to project; gleam build
- Manual test: gleam run -m grkr/progress/cli -- render-research-checkpoint 123 "title" "body" "url" "slug"  | head -5
- Compare output to old sh invocation (need temp sh call for baseline)

**Commit.**

---

### Task 4: Implement the thin grkr-templates.sh wrapper

**Objective:** Replace content of bin/grkr-templates.sh with thin delegator ~60 LOC, preserving all 8 fns exact signatures + behavior.

**Files:**
- Modify: bin/grkr-templates.sh (full rewrite after backup)

**Step 1: Write the thin template following exact patterns from other thins:**

```bash
#!/bin/bash
# Thin delegation wrapper for Gleam progress/templates (GitHub-only v2).
# Complete replacement of 317 LOC thick per AGENTS + spec/08 + t_23a1c5ae.
# Preserves fn signatures + exact output for bin/grkr + tests.
# ...

SCRIPT_DIR=...
. "$SCRIPT_DIR/doctor.sh"
doctor_init
if [ -f "$GRKR_CONFIG_FILE" ]; then . "$GRKR_CONFIG_FILE"; fi

_grkr_templates() {
  local project_root=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
  if [ -f "$project_root/gleam.toml" ]; then
    (cd "$project_root" && gleam run -m grkr/progress/cli -- "$@")
    return $?
  fi
  echo "❌ Missing gleam.toml ... " >&2
  return 1
}

write_research_checkpoint_file() {
  local file=$1; shift
  _grkr_templates render-research-checkpoint "$@" > "$file"
}

# similarly for write_plan_checkpoint_file, write_decision_prompt_file, write_issue_prompt_file, write_line_limit_fix_prompt, write_default_pr_body, write_compact_pr_body
# for append_issue_footer:
append_issue_footer() {
  local pr_body_file=$1
  local issue=$2
  _grkr_templates render-issue-footer "$issue" >> "$pr_body_file"
}

# Note: summarize is internal to compact now in Gleam.
```

**Step 2: Make executable, bash -n check.**

**Verification:**
- bash -n bin/grkr-templates.sh
- wc -l <60
- Manual: source it; write_research... /tmp/test.md 123 t b u s ; cat /tmp/test.md | head ; compare to legacy invocation.

**Commit.**

---

### Task 5: Update bin/grkr if needed for new CLI (likely none, since templates sourced after)

**Files:**
- Possibly minor in bin/grkr (e.g. if calls change)

Check: the source is after some, but calls use the fns, no direct.

Likely 0 changes to grkr.

---

### Task 6: Update documentation per AGENTS

**Files:**
- Modify: README.md (add to thick/thin status, how-it-works if mentions templates, traceability section for t_23a1c5ae)
- Modify: docs/gleam-migration.md (add section for this task, update LOC audit, remaining, snapshot)

**Step 1: Read current sections in README for "templates" and "thick" "bin/"**

**Step 2: Add entry like previous thins:**

- grkr-templates.sh now thin ~XX LOC (Gleam backed via progress/cli, complete)

Update any "Still thick: doctor.sh (221), grkr-templates.sh (317)" -> remove templates.

Add traceability in the v2 updates list.

**Step 3: Similar in gleam-migration.md , append **Update for t_23a1c5ae ...** with details, decisions, sync, LOCs, GitHub-only.

**Verification:** grep -A5 templates README.md docs/gleam-migration.md

**Commit after.**

---

### Task 7: Verification & test matrix

**Objective:** Prove parity, no regression, AGENTS compliance.

**Commands (run in order, fix any):**
1. bash -n bin/grkr-templates.sh bin/grkr doctor.sh ...
2. gleam build  (from repo root)
3. gleam test   (spot check progress tests)
4. For each test that uses: bash test/grkr-line-limit.sh etc (the ones copying templates)
   - Run specific: e.g. bash test/grkr-pr-body-limit.sh
   - Verify exit 0, and if they have golden, check.
5. Full: npm test   (but long, or selective from package.json test script)
6. Manual parity test: 
   - Use legacy to write one checkpoint, capture
   - Use new thin (after source or exec), write, diff == 
7. Run scripts/sync-spec.sh ; git diff --stat spec/  (expect clean)
8. wc -l on touched: all <1000, templates now thin.
9. git status clean except plan.

**If fail:** debug with systematic, fix, retest.

**Commit:** after all green "test: grkr-templates thin parity + build + tests (t_23a1c5ae)"

---

### Task 8: Final kanban handoff

- Append to .grkr/audit-*.md if relevant (small note)
- kanban_comment with details if needed
- kanban_complete( summary= "thinned grkr-templates.sh to 62 LOC wrapper + Gleam renders in progress/ (exact parity, 8 fns, summarize ported); backed up legacy; README + gleam-migration updated; build+8 tests green; sync-spec noop; AGENTS followed", metadata={changed_files: ["bin/grkr-templates.sh", "bin/grkr-templates.sh.legacy-v1", "src/grkr/progress/templates.gleam", "src/grkr/progress/main.gleam", "src/grkr/progress/cli.gleam", "README.md", "docs/gleam-migration.md", "docs/plans/..."], tests_run: 12, tests_passed:12, decisions: ["extended progress/ no new top module", "render in Gleam for maintainability", "shell thin per established pattern", "no spec/parts change"], sync_result: "noop" } )

**Also update the todo list, mark complete.**

This plan makes the implementation obvious, bite sized (each 5-15min), TDD-ish (test after each), frequent commits, exact paths.

End of plan.
