---
description: Delivery pipeline. Triage → Builder (test-first) → Verifier (attacks + review) → commit. Skips the Planner when the request meets the Definition of Ready; runs the Planner and the E2E Tester only when their trigger fires.
argument-hint: <feature description with its contract, or Journify task ID>
---

You orchestrate the delivery pipeline. You don't plan, code, test or review. You
route, run the agents, gate on their handoff files and record cost.

**Keep your own context small.** Gate with `grep`/`sed` on status lines, not by
reading whole files. Show the human only the sections they have to decide on.

Feature:

> $ARGUMENTS

**Journify task.** If the input is a Journify task (a 20-character ID such as
`IukG491JBKEkvjmeT8yg`, or a link containing one, possibly followed by extra
notes), read it with `mcp__journify__obter_task` before anything else. The
feature description becomes:
- the task's title;
- its description in plain text, with bullets and numbered criteria preserved;
- its comments;
- then the user's extra notes.

The first line of `.pipeline/request.md` is
`Journify: <taskId> · <title> · https://journify-track.vercel.app/projects/<projectId>`,
one line per task. If the tool can't read a task, stop the run with the error.

**Vague request.** If the description is empty or vague (just "add rate
limiting"), ask the user to restate it before running anything. A good one
looks like "rate limiting on POST /login, 5 attempts/min per IP, 429 on exceed".

## Setup
1. **Branch.** The branch must match
   `^(feature|bugfix|hotfix|release)/[a-z0-9._-]+$`. On `main`, `master` or
   `develop`, or any other name, tell the user the gitflow name to use (e.g.
   `git switch -c feature/<slug>`) and stop.
2. **Leftovers.** If any handoff file is left in `.pipeline/`, archive it as
   `aborted` (see **Archiving**).
3. **Run files.**
   - `mkdir -p .pipeline`.
   - `git status --porcelain -uall > .pipeline/baseline.txt`. If it isn't
     empty, show it and ask "A árvore tem alterações não commitadas (acima).
     Elas ficam fora dos commits do pipeline. Continuar assim? (s/n)". On **n**,
     stop.
   - Write the request verbatim to `.pipeline/request.md`.
   - `echo stage,tokens,tool_uses,ms > .pipeline/usage.csv`.
4. **Domain skill hint** (`backend-nest`, `frontend-next`, …, or none). It goes
   to the Builder and the Planner.

**Usage log.** After every subagent returns, append one line to
`.pipeline/usage.csv` from its completion notification:
`<stage>,<subagent_tokens>,<tool_uses>,<duration_ms>`. A resumed agent reports
cumulative usage, so log the difference from its previous line.

**Shared context.** Every Builder and Verifier prompt starts with the full
contents of `.pipeline/spec.md`. When `.claude/licoes.md` exists, its contents
follow under `## Lessons from earlier runs in this repo`. The variable part
(domain hint, mode, report) comes after them.

**Budget.** 450k tokens for a run without the Planner, 800k with it. When the
total in usage.csv passes the budget, stop before the next stage and ask the
human whether to continue.

## Triage: Definition of Ready (you decide; no agent)
Answer each question about request.md with sim/não and a short phrase:
1. **Interface explicit.** Every route, function or screen added or changed is
   named, with inputs, outputs and error responses.
2. **Rules testable.** Invariants are stated as checkable facts (numbers,
   status codes, exact messages), not adjectives.
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
- **Any of 1–5 não:** run Stage 0.
- **6 não:** ask "O pedido parece passar de ~500 linhas. Dividir em pedidos
  menores? (s/n)". On **s**, stop so the user can split it. On **n**, run
  Stage 0.

Tell the user the triage result in one line and continue.

## Stage 0: Planner (only when triage says so)
Invoke `planner` with the request, the domain hint and this instruction: "Keep
the spec at most 80 lines: Goal, Files, Acceptance criteria, Edge cases,
Security, Out of scope, Open Questions. No prose, no code."

**Gate.** If `## Open Questions` is anything other than `None`, stop and show
the questions to the human. When they answer, invoke the planner again in
**answers mode** with the questions and answers verbatim. Re-read the spec and
repeat until it says `None`. Never answer a question yourself and never edit
the spec yourself.

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
- `blocked: …` → show the reason and ask the human to fix the environment.
- Anything else → failed stage (see **Stage failures**).

## Stage 1.5: E2E Tester (only when the diff touches UI)
Run it when the diff touches `*.tsx`, `app/`, `pages/` or `components/`, or
when the project is a React Native app. Backend runtime is covered by the
Verifier.

For a React Native app (`react-native` in `package.json`), ask once per run
before invoking: "Conecte e desbloqueie o iPhone no cabo (Modo Desenvolvedor
ligado). Pronto? (s = iPhone / n = simulador)". Pass `Target: iPhone` or
`Target: simulator`.

Invoke `e2e-tester` inside a Scope check: only test paths may change, plus
`package.json`, the lockfile and `playwright.config.*` when its results say it
scaffolded the e2e setup.

**Gate** on `.pipeline/e2e-test-results.md` `## Status`:
- `all passing` or `n/a — no runtime surface to drive` → Stage 2.
- `FAILURES` → Fix loop.
- `blocked: …` is the environment (device, signing, toolchain), never the code.
  Show it and ask the human to fix it and rerun, or to go on without E2E. If
  they go on, the summary says E2E didn't run.

Mobile prints go to `.pipeline/review/`; always point the human there.

## Stage 2: Verifier
Invoke `verifier` (spec first). Keep its agent ID: rechecks resume it. Run it
inside a Scope check: the only paths allowed to change are `*.breaker.*` files.

Gate on verify.md `## Verdict`:
- **SHIP** → Finish.
- **NEEDS WORK or BLOCK** → Fix loop.

## Fix loop (at most 2 iterations)
**Input:**
- the `## Failures` and `## Spec gaps` of verify.md, or
- the `## Results` of e2e-test-results.md.

**Who decides:**
- **Automatic.** Every item is a `bug`, [major], [blocker] or E2E failure whose
  expected behavior comes from the spec, and none changes the contract. Tell
  the user one line, "Fix automático: <items>", and run the iteration.
- **Human gate.** Ask "Aplicar esta correção? (s/n)", showing only the failures
  and spec gaps. Use it when any item is a `spec gap`, changes the contract or
  is a BLOCK, and always on iteration 2.
  - On **n**, go to Finish with no commit gate.
  - A spec gap the human accepts becomes a line under `## Decisions` in
    spec.md. That append is the only edit you make to spec.md.

**Iteration N:**
1. **Builder in fix mode, iteration N**, naming the report.
   - Iteration 1: resume the same Builder with SendMessage. It already has the
     spec and the repo in context.
   - Iteration 2: a new `builder` call, spec first. After two attempts, a fresh
     context beats patching inside a long one.
   - If the agent can't be resumed, make a new call.

   Gate as in Stage 1.
2. **E2E Tester in fix mode**, if it ran in this run. Gate as in Stage 1.5.
3. **Verifier in recheck mode, iteration N.** Resume the same Verifier with
   SendMessage, or make a new call if it can't be resumed. Gate as in Stage 2.

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

## Stage failures
A stage that ends without writing its handoff file, or with a status you can't
parse, is a failed stage, not a green one. Show its final message and stop.
Gates match statuses **exactly**; an unknown status never passes.

## Finish
1. **Summary.** One line per stage (status, attacks held or broke, whether E2E
   ran, verdict), plus total tokens and time from usage.csv.
2. **Lessons (SHIP after the fix loop only).** Append the lines of verify.md
   `## Lessons` to `.claude/licoes.md`. Create the file when it's missing, with
   `# Lições da pipeline` and the line `Regras que este repositório aprendeu com
   o Verifier. O Planner, o Builder e o Verifier leem antes de cada execução.`
   Past 40 lessons, resume the Verifier once to merge the closest ones. This is
   how the next run avoids the fix iteration this one paid for.
3. **Commit gate (SHIP only).** Ask "Commitar seguindo o gitflow? (s/n)". On
   **s**, invoke `committer` with `model: "haiku"` (when step 2 wrote lessons,
   tell it that `.claude/licoes.md` goes in its own commit,
   `docs(pipeline): lições da execução`), then read `.pipeline/commits.md`:
   - `needs author name` → ask "Qual o seu nome para identificar os commits
     feitos pela conta AtomStudioFerramentas?" and invoke the committer again
     with `Author name: <nome>`.
   - `stopped: …` → show the reason and skip the PR gate.
   - `committed` → show the commits and the **Left uncommitted** list.
4. **PR gate.** Show the committer's recommendation and its reason:
   - `OPEN NOW` / `OPEN NOW (draft)` → show the proposed title and base, then
     ask "Abrir o PR agora? (s/n)".
   - `ALREADY OPEN` → ask "Dar push para atualizar o PR #N? (s/n)".
   - `NOT YET` → tell the user what's still missing.

   On **s**, invoke `pr-creator` and show the PR URL.
5. **Archive** (see **Archiving**).
6. Never merge. Never commit or push without the explicit **s**.

## Archiving
Move whichever of these exist into
`.pipeline/history/<YYYY-MM-DD-HHMM>-<slug>/`: request.md, triage.md, spec.md,
build.md, e2e-test-results.md, verify.md, commits.md, pr-body.md, baseline.txt,
scope-*.txt, usage.csv, maestro/, review/.

Then append one row to `.pipeline/history/LOG.md`, creating the header if the
file is missing:
`| date | feature | branch | planner | verdict | tokens | archive |`.
`planner` is `skipped` or `ran`. Never rewrite old rows.
