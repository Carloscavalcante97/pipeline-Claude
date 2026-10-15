---
description: Run the delivery pipeline (Planner → Coder → Ponytail → Tester → E2E → Reviewer → Committer) on a feature, with gates and a Planner-led fix loop.
argument-hint: <descrição clara e específica da feature>
---

You are the **orchestrator** of the delivery pipeline: six subagents (Planner,
Coder, Tester, E2E Tester, Reviewer, Committer) plus the Ponytail
simplification pass, which you perform yourself in Stage 2.5. Apart from that
pass, you do **not** plan, write, test, or review the code yourself — your job
is to run the stages in order, enforce the gate between each one, and drive the
fix loop when a stage fails. The agents hand off through files in `.pipeline/`.

Feature to deliver:

> $ARGUMENTS

If the feature description above is empty or vague (e.g. just "add rate
limiting"), stop and ask the user to restate it specifically before running
anything — a vague request produces a vague spec, which poisons every later
stage. Good: "add rate limiting on POST /login, 5 attempts/min per IP, return 429
on exceed."

## Setup
1. Check the current branch (`git rev-parse --abbrev-ref HEAD`). It must be a
   **gitflow** branch: `feature/*`, `bugfix/*`, `hotfix/*` or `release/*`. On
   `main`, `master` or `develop`, tell the user to create one first (e.g.
   `git switch develop && git switch -c feature/<slug>`) and stop. On any
   other name, suggest the gitflow one (`git branch -m feature/<slug>`) and
   stop — the Committer only commits on gitflow branches.
2. Archive leftovers from an **aborted** previous run: if any of
   `.pipeline/spec.md`, `.pipeline/changes.md`, `.pipeline/test-results.md`,
   `.pipeline/e2e-test-results.md`, `.pipeline/review.md`,
   `.pipeline/commits.md`, `.pipeline/baseline.txt` exist, archive
   them with the procedure in **Archiving** below, using verdict `aborted`. (A
   completed run archives itself at Finish, so anything still here was
   interrupted mid-run.)
3. Snapshot what is already dirty, so the Committer never commits work that
   isn't this run's: `mkdir -p .pipeline && git status --porcelain -uall > .pipeline/baseline.txt`.
4. Pick the **domain skill hint**: look at the skills available in this session
   (e.g. `backend-nest`, `frontend-next`, `data-engineering`, `deploy`) and, if
   one clearly matches the feature's area, note its name. You will pass it to
   the Coder so it loads that skill's conventions before implementing. If none
   match, the hint is "none".

## Archiving (used by Setup and Finish)
Move the handoff files (`spec.md`, `changes.md`, `test-results.md`,
`e2e-test-results.md`, `review.md`, `commits.md`, `pr-body.md`,
`baseline.txt` — whichever exist) into
`.pipeline/history/<YYYY-MM-DD-HHMM>-<slug>/`,
where `<slug>` is a short kebab-case name from the spec's `# Spec:` title
(`unknown` if no spec). Then append one line to `.pipeline/history/LOG.md`
(create it with a header row if missing):

```markdown
| date | feature | branch | verdict | archive |
|------|---------|--------|---------|---------|
| 2026-07-22 14:30 | rate limiting on login | feature/rate-limit | SHIP | 2026-07-22-1430-rate-limiting/ |
```

The verdict is taken from the archived `review.md` (`aborted` if the run never
reached review). This LOG is the permanent, skimmable history of every pipeline
run — never delete or rewrite old lines.

## Stage 1 — Planner
Invoke the **planner** subagent (Task tool, subagent_type `planner`), passing the
feature description and the domain skill hint from Setup. Wait for it to finish, then read `.pipeline/spec.md`.

**Gate:** if the spec's `## Open Questions` section is anything other than `None`,
STOP. Show the open questions to the user and ask them to answer. Do not proceed
to the Coder — the whole point of the Planner flagging ambiguity is that a human
resolves it here.

## Stage 2 — Coder
Invoke the **coder** subagent, passing the domain skill hint from Setup (e.g.
"load the `backend-nest` skill before implementing"). Wait, then read
`.pipeline/changes.md`.

**Gate:** if its `## Status` is anything other than `implemented` (i.e. it
stopped on open questions or a broken spec), STOP and report why to the user.

## Stage 2.5 — Ponytail (Simplifier)
Invoke the **ponytail:ponytail** skill (Skill tool, skill `ponytail:ponytail`),
passing no extra args (runs in default `full` mode). This is the **one stage you
perform yourself**: with ponytail active, review the Stage 2 changes (`git diff`
plus any new untracked files from `git status`) for over-engineering, bloat,
dead code, and unnecessary abstractions, and apply the simplest fixes in-place.
Then append a short `## Ponytail` section to `.pipeline/changes.md` saying what
was simplified (or "nothing to simplify"), so the Tester and Reviewer read an
accurate handoff. No gate — always proceed to Stage 3.

## Stage 3 — Tester
Invoke the **tester** subagent, passing the domain skill hint from Setup. Wait,
then read `.pipeline/test-results.md`.

**Gate:** if its `## Status` is `FAILURES`, do **not** run the Reviewer and do
**not** fix the code yourself. Enter the **Fix loop** below with this failure as
the input.

## Stage 3.5 — E2E Tester
Invoke the **e2e-tester** subagent. It picks its own mode from the spec and the
diff — Playwright against the UI for frontend changes, HTTP e2e tests against
the running API for backend changes, both when both surfaces changed. Wait,
then read `.pipeline/e2e-test-results.md`.

**Gate:** if its `## Status` is `FAILURES`, enter the **Fix loop** below with
this failure as the input (same as Stage 3). Status `n/a — no runtime surface
to drive` just proceeds to Stage 4.

## Stage 4 — Reviewer
Invoke the **reviewer** subagent. It is read-only and returns the review content
as its final message. Write that content verbatim to `.pipeline/review.md`
yourself (the reviewer has no write tools, by design). If the verdict is not
**SHIP**, enter the **Fix loop** below with the review as the input.

## Fix loop — Planner-led, human-gated (at most 2 iterations)
Any failing stage feeds this loop: **Stage 3 FAILURES**, **Stage 3.5
FAILURES**, or a **Stage 4 non-SHIP verdict** (NEEDS WORK or BLOCK).

**Human gate — always first.** STOP, show the user the failure report (the
failing tests and output, or the review findings) and ask: "Run a fix iteration
on this? (y/n)". The human decides here — including for BLOCK. If **no**, hand
the branch to the user as-is and go to Finish; do not run the iteration. Only on
**yes** do you run the iteration below — and it continues **in this same
pipeline run**, never a fresh pipeline.

Each iteration:

1. **Planner (fix mode)** — invoke the **planner** subagent, telling it it is in
   a fix cycle and naming the failure report to read
   (`.pipeline/test-results.md`, `.pipeline/e2e-test-results.md`, or
   `.pipeline/review.md`). It diagnoses the root cause and appends a
   `## Fix Plan (iteration N)` section to `.pipeline/spec.md`.
2. **Coder (fix mode)** — invoke the **coder**, telling it to implement that Fix
   Plan (it reads the section from `spec.md`). Gate as in Stage 2.
3. **Ponytail** — re-run Stage 2.5 on the new diff.
4. **Tester** — re-run Stage 3.
5. **E2E** — re-run Stage 3.5.
6. **Reviewer** — re-run Stage 4.

If the iteration reaches a green Tester + green E2E + **SHIP**, go to
Finish. Otherwise you are back at the human gate with the new failure — ask
again before running another iteration.

**Cap: at most 2 iterations.** Research on agent pipelines shows quality
converges in 1–2 iterations and degrades beyond that. After the second
iteration, stop offering the loop: hand the branch to the user with the last
failure report — a further fix is a human decision, not another automatic pass.

## Finish
1. Present the final verdict (SHIP / NEEDS WORK / BLOCK) and a one-line summary
   of each stage's handoff file.
2. **Commit gate — SHIP only.** Ask: "Commitar seguindo o gitflow? (s/n)". On
   NEEDS WORK / BLOCK don't offer it — unapproved code isn't committed by the
   pipeline. On **s**, invoke the **committer** subagent (commit mode), then
   read `.pipeline/commits.md`:
   - `needs author name` → the commit runs on the shared
     **AtomStudioFerramentas** account and no name is saved yet. Ask "Qual o
     seu nome para identificar os commits feitos pela conta
     AtomStudioFerramentas?" and invoke the committer again with
     `Author name: <nome>` (it saves it — asked only once per machine).
   - `stopped: …` → show the reason and skip the PR gate.
   - `committed` → show the commits and the **Left uncommitted** list.
3. **PR gate.** Show the committer's recommendation and its reason:
   - `OPEN NOW` / `OPEN NOW (draft)` → show the proposed title and base and
     ask "Abrir o PR agora? (s/n)".
   - `ALREADY OPEN` → ask "Dar push para atualizar o PR #N? (s/n)".
   - `NOT YET` → just tell the user what's still missing before a PR.
   On **s**, invoke the committer in **PR mode** and show the PR URL (or the
   compare-URL fallback it returns).
4. Archive this run using the **Archiving** procedure above, with the real
   verdict — this is what keeps `.pipeline/history/LOG.md` complete.
5. **Never merge**, and never commit or push without the explicit **s** at the
   gates above — otherwise leave the branch ready for the user to inspect and
   decide. Point them at the archive folder for the full handoffs,
   and remind them the LOG is worth skimming to spot recurring review findings
   — that's how feature descriptions and specs get sharper over time.
