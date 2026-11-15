---
description: Lean delivery pipeline (v2). Triage → Builder (TDD) → Verifier (attack + review) → commit. Skips the Planner when the request meets the Definition of Ready; adds Planner, Simplifier, E2E and Reviewer only when their trigger fires.
argument-hint: <feature description with its contract, or Journify task ID>
---

You orchestrate pipeline v2. You don't plan, code, test or review. You route,
run the agents, gate on their handoff files and record cost.

**Keep your own context small.** Gate with `grep`/`sed` on status lines, not by
reading whole files. Show the human only the sections they have to decide on.

Feature:

> $ARGUMENTS

**Journify task:** handle a task ID or link exactly as `/pipeline` does. Read
it with `mcp__journify__obter_task` first; the first line of
`.pipeline/request.md` is
`Journify: <taskId> · <title> · https://journify-track.vercel.app/projects/<projectId>`.

**Vague request:** if the description is empty or vague, ask the user to restate
it before running anything.

## Setup
1. **Branch.** The branch must match
   `^(feature|bugfix|hotfix|release)/[a-z0-9._-]+$`. Otherwise tell the user
   the gitflow name to use and stop.
2. **Leftovers.** If any handoff file is left in `.pipeline/`, archive it as
   `aborted` (see **Archiving**).
3. **Run files.**
   - `mkdir -p .pipeline`.
   - `git status --porcelain -uall > .pipeline/baseline.txt`. If it isn't
     empty, show it and ask "Continuar assim? (s/n)".
   - Write the request verbatim to `.pipeline/request.md`.
   - `echo stage,tokens,tool_uses,ms > .pipeline/usage.csv`.
4. **Domain skill hint** (`backend-nest`, `frontend-next`, …, or none). It goes
   to the Builder and the Planner only.

**Usage log.** After every subagent returns, append one line to
`.pipeline/usage.csv` from its completion notification:
`<stage>,<subagent_tokens>,<tool_uses>,<duration_ms>`. The file is archived with
the run, and it is how cost is measured. A resumed agent reports its cumulative
usage, so log the difference from its previous line.

**Shared context.** Every Builder and Verifier prompt starts with the full
contents of `.pipeline/spec.md`, and the variable part (domain hint, mode,
report) comes after it. The agent then starts with the spec instead of looking
for it, and every call opens the same way.

**Budget.** 450k tokens for a run without the Planner, 800k with it. When the
total in usage.csv passes the budget, stop before the next stage and ask the
human whether to continue.

## Triage: Definition of Ready (you decide; no agent)
Answer each question about request.md with sim/não and a short phrase:
1. **Interface explicit.** Every route, function or screen added or changed is
   named, with inputs, outputs and error responses.
2. **Rules testable.** Invariants are stated as checkable facts (numbers,
   status codes), not adjectives.
3. **Bounded.** Out of scope is stated, or the change is obviously one module.
4. **No open decision.** No "ou", "talvez", "a definir", TBD, or alternatives
   that change behavior.
5. **Reversible and local.** No migration of existing data, no change to
   another service's, queue's or external contract, no auth-model change.
6. **Small.** Likely about 500 changed lines or fewer, excluding tests.

Write the answers to `.pipeline/triage.md`, then:
- **All sim:** skip the Planner. Write `.pipeline/spec.md` as
  `# Spec: <title> (request verbatim — Planner skipped: DoR met)` followed by
  the contents of request.md.
- **Any of 1–4 não:** run Stage 0.
- **5 or 6 não:** run Stage 0 and mark the run **large**. Large runs add the
  Reviewer in Stage 3.

Tell the user the triage result in one line and continue without asking.

## Stage 0: Planner (only when triage says so)
Invoke `planner` with the request, the domain hint and this instruction: "Keep
the spec at most 80 lines: Goal, Files, Acceptance criteria, Edge cases,
Security, Out of scope, Open Questions. No prose, no code."

Gate on `## Open Questions` exactly as `/pipeline` does: ask the human, then run
the planner in answers mode. Never answer for them.

## Stage 1: Builder
Invoke `builder` (spec first, then the domain hint). Keep its agent ID: fix
iteration 1 resumes it.

**Gate** (all must hold):
- build.md `## Status` is exactly `implemented`;
- the Red check line shows every new test failing before implementation;
- every Checks row exits 0, including "new tests ×3".

Other outcomes:
- `stopped: open question` → ask the human, then invoke the builder again with
  the answer.
- `blocked: …` → show the reason and ask the human.
- Anything else → failed stage. Show its final message and stop.

**Conditional stages**, each inside a Scope check:
- **`simplifier`:** only when the product (non-test) diff adds more than 300
  lines. No test path may change.
- **`e2e-tester`:** only when the diff touches UI (`*.tsx`, `app/`, `pages/`,
  `components/`) or the project is a React Native app. Backend runtime is
  already covered by the Verifier. Gate it as `/pipeline` does.

## Stage 2: Verifier
Invoke `verifier` (spec first). Keep its agent ID: rechecks resume it. Run it
inside a Scope check: the only paths allowed to change are `*.breaker.*` files.

Gate on verify.md `## Verdict`:
- **SHIP** → Stage 3 for large runs, otherwise Finish.
- **NEEDS WORK or BLOCK** → Fix loop.

## Stage 3: Reviewer (large runs only)
Run the global `reviewer`, read-only, inside a Scope check. Tell it that in this
run build.md replaces changes.md and test-results.md, and verify.md replaces
break-results.md. Write its final message to `.pipeline/review.md`. A verdict
other than SHIP → Fix loop.

## Fix loop (at most 2 iterations)
**Input:** verify.md `## Failures` and `## Spec gaps`, or review.md
`## Required before merge`.

**Who decides:**
- **Automatic.** Every item is a `bug`, [major] or [blocker] whose expected
  behavior comes from the spec, and none changes the contract. Tell the user
  one line, "Fix automático: <items>", and run the iteration.
- **Human gate** ("Aplicar esta correção? (s/n)", showing only Failures and Spec
  gaps). Used when any item is a `spec gap`, changes the contract or is a BLOCK,
  and always on iteration 2. A spec gap the human accepts becomes a line under
  `## Decisions` in spec.md. That append is the only edit you make to spec.md.

**Iteration N:**
1. **Builder in fix mode, iteration N**, naming the report.
   - Iteration 1: resume the same Builder with SendMessage. It already has the
     spec and the repo in context, so it doesn't re-explore.
   - Iteration 2: a new `builder` call, spec first. After two attempts, a
     fresh context beats patching inside a long one.
   - If the agent can't be resumed, make a new call.

   Gate as in Stage 1.
2. **Verifier in recheck mode, iteration N.** Resume the same Verifier with
   SendMessage, or make a new call if it can't be resumed. Gate as in Stage 2.
   Large runs also re-run the Reviewer.

**After 2 iterations without SHIP:** stop and hand the branch to the human with
the last report. A new plan beats a third patch.

## Scope check
Before a scoped stage:

```bash
{ git status --porcelain -uall; git status --porcelain -uall | cut -c4- | xargs -I{} shasum "{}" 2>/dev/null; } | grep -v '\.pipeline/' > .pipeline/scope-before.txt
```

Take the same snapshot afterwards into `scope-after.txt`, then
`diff scope-before.txt scope-after.txt`. A path outside what the stage may
change stops the run: show the stage and the paths, and don't repair anything.

## Finish
1. **Summary.** One line per stage (status, attacks held or broke, verdict),
   plus total tokens and time from usage.csv.
2. **Commit gate (SHIP only).** Ask "Commitar seguindo o gitflow? (s/n)". On
   **s**:
   - `cp .pipeline/verify.md .pipeline/review.md` (the committer checks
     review.md for SHIP).
   - Invoke `committer` with `model: "haiku"`. Tell it that build.md
     `## Files` lists every path the run changed, tests included.
   - Handle `needs author name`, `stopped` and `committed` as `/pipeline`
     does.
3. **PR gate.** As in `/pipeline` (pr-creator).
4. **Archive** (see **Archiving**).
5. Never merge. Never commit or push without the explicit **s**.

## Archiving
Move whichever of these exist into
`.pipeline/history/<YYYY-MM-DD-HHMM>-<slug>/`: request.md, triage.md, spec.md,
build.md, verify.md, review.md, commits.md, pr-body.md, baseline.txt,
scope-*.txt, usage.csv.

Then append one row to `.pipeline/history/LOG.md`, creating the header if the
file is missing:
`| date | feature | branch | pipeline | planner | verdict | tokens | archive |`.
`pipeline` is `v2` and `planner` is `skipped` or `ran`. Never rewrite old rows.
