---
description: Run the 5-stage delivery pipeline (Planner → Coder → Ponytail → Tester → Reviewer) on a feature, with gates between each stage.
argument-hint: <descrição clara e específica da feature>
---

You are the **orchestrator** of a five-stage delivery pipeline (four subagents
plus the Ponytail simplification pass, which you perform yourself in Stage 2.5).
Apart from that pass, you do **not** plan, write, test, or review the code
yourself — your job is to run the stages in order and enforce the gate between
each one. The agents hand off through files in `.pipeline/`.

Feature to deliver:

> $ARGUMENTS

If the feature description above is empty or vague (e.g. just "add rate
limiting"), stop and ask the user to restate it specifically before running
anything — a vague request produces a vague spec, which poisons every later
stage. Good: "add rate limiting on POST /login, 5 attempts/min per IP, return 429
on exceed."

## Setup
1. Check the current branch (`git rev-parse --abbrev-ref HEAD`). If it's `main`
   or `master`, tell the user to create a feature branch first and stop — the
   pipeline edits files and is meant to run on a throwaway branch.
2. Archive-then-reset the handoff folder so a previous run can't leave
   misleading files but its history is never lost: if any of `.pipeline/spec.md`,
   `.pipeline/changes.md`, `.pipeline/test-results.md`, `.pipeline/review.md`
   exist, move them into `.pipeline/history/<YYYY-MM-DD-HHMM>-<slug>/`, where
   `<slug>` is a short kebab-case name taken from the old spec's `# Spec:` title
   (use `unknown` if there is no spec). This archives every previous run —
   including aborted ones — and leaves `.pipeline/` clean for the new run.

## Stage 1 — Planner
Invoke the **planner** subagent (Task tool, subagent_type `planner`), passing the
feature description. Wait for it to finish, then read `.pipeline/spec.md`.

**Gate:** if the spec's `## Open Questions` section is anything other than `None`,
STOP. Show the open questions to the user and ask them to answer. Do not proceed
to the Coder — the whole point of the Planner flagging ambiguity is that a human
resolves it here.

## Stage 2 — Coder
Invoke the **coder** subagent. Wait, then read `.pipeline/changes.md`.

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
Invoke the **tester** subagent. Wait, then read `.pipeline/test-results.md`.

**Gate:** if its `## Status` is `FAILURES`, STOP. Show the failing tests and their
output to the user. Do **not** run the Reviewer — and do not try to fix the code
yourself. A failing pipeline ends here, with the branch left for the user.

## Stage 4 — Reviewer
Invoke the **reviewer** subagent. It is read-only and returns the review content
as its final message. Write that content verbatim to `.pipeline/review.md`
yourself (the reviewer has no write tools, by design).

## Finish
Present the final verdict (SHIP / NEEDS WORK / BLOCK) and a one-line summary of
each stage's handoff file. **Never merge, commit, or push** — leave the branch
ready for the user to inspect and decide. Remind them it's worth skimming the
`.pipeline/*.md` files even on SHIP, since that's how they learn to write sharper
feature descriptions over time.
