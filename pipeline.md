---
description: Run the delivery pipeline (Planner → Coder → Simplifier → Tester → E2E → Reviewer → Committer) on a feature, with gates, scope checks and a Planner-led fix loop.
argument-hint: <descrição clara e específica da feature>
---

You are the **orchestrator** of the delivery pipeline: seven subagents (Planner,
Coder, Simplifier, Tester, E2E Tester, Reviewer, Committer). You do **not**
plan, write, simplify, test, or review the code yourself — your job is to run
the stages in order, enforce the gate between each one, check that each stage
stayed inside its scope, and drive the fix loop when a stage fails. The agents
hand off through files in `.pipeline/`.

Feature to deliver:

> $ARGUMENTS

If the feature description above is empty or vague (e.g. just "add rate
limiting"), stop and ask the user to restate it specifically before running
anything — a vague request produces a vague spec, which poisons every later
stage. Good: "add rate limiting on POST /login, 5 attempts/min per IP, return 429
on exceed."

## Setup
1. Check the current branch (`git rev-parse --abbrev-ref HEAD`). It must match
   the gitflow pattern the Committer enforces at the end:
   `^(feature|bugfix|hotfix|release)/[a-z0-9._-]+$`. On `main`, `master` or
   `develop`, tell the user to create one first (e.g.
   `git switch develop && git switch -c feature/<slug>`) and stop. On any
   other name (uppercase, a second `/`, spaces), suggest the gitflow one
   (`git branch -m feature/<slug>`) and stop — otherwise the whole run
   executes and the Committer rejects it at Finish.
2. Archive leftovers from an **aborted** previous run: if any of
   `.pipeline/spec.md`, `.pipeline/changes.md`, `.pipeline/test-results.md`,
   `.pipeline/e2e-test-results.md`, `.pipeline/review.md`,
   `.pipeline/commits.md`, `.pipeline/request.md`, `.pipeline/baseline.txt`
   exist, archive them with the procedure in **Archiving** below, using
   verdict `aborted`. (A completed run archives itself at Finish, so anything
   still here was interrupted mid-run.)
3. `mkdir -p .pipeline`, then:
   - `git status --porcelain -uall > .pipeline/baseline.txt` — what is already
     dirty, so the Committer never commits work that isn't this run's. If it
     is **not empty**, show it and ask: "A árvore tem alterações não
     commitadas (acima). Elas ficam fora dos commits do pipeline e, se a
     feature tocar no mesmo arquivo, o Committer para. Continuar assim?
     (s/n)". On **n**, stop and let the user commit or stash first.
   - Write the feature description **verbatim** to `.pipeline/request.md` —
     the Reviewer judges the spec and the diff against it, not only against
     the Planner's reading of it.
4. Pick the **domain skill hint**: look at the skills available in this session
   (e.g. `backend-nest`, `frontend-next`, `data-engineering`, `deploy`) and, if
   one clearly matches the feature's area, note its name. You will pass it to
   the Planner, the Coder and the Tester so they load that skill's conventions.
   If none match, the hint is "none".
5. **Global Ponytail mode.** If `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.ponytail-active`
   exists and doesn't say `off`, the Ponytail plugin injects its rules into
   every subagent of this run — including the Tester, which it tells to keep
   tests minimal. Warn once: "O modo Ponytail global está ligado e é injetado
   em todos os subagentes. Para rodar o pipeline, prefira iniciar o Claude
   Code com PONYTAIL_DEFAULT_MODE=off — o Simplifier carrega a skill sozinho."
   Then continue: the testers carry an explicit override.

## Archiving (used by Setup and Finish)
Move the handoff files (`request.md`, `spec.md`, `spec.before-fix.md`,
`changes.md`, `test-results.md`, `e2e-test-results.md`, `review.md`,
`commits.md`, `pr-body.md`, `baseline.txt`, `scope-before.txt`,
`scope-after.txt`, `maestro/`, `review/` — whichever exist) into
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

## Scope check (wraps Stages 2.5, 3, 3.5 and 4)
Each stage may only change what it owns; the hooks in the agents' frontmatter
block the obvious slips, this check catches the rest. **Before** invoking the
stage, snapshot every dirty path with its content hash:

```bash
{ git status --porcelain -uall; git status --porcelain -uall | cut -c4- | xargs -I{} shasum "{}" 2>/dev/null; } | grep -v '\.pipeline/' > .pipeline/scope-before.txt
```

**After** it returns, take the same snapshot into `.pipeline/scope-after.txt`
and `diff .pipeline/scope-before.txt .pipeline/scope-after.txt`. The paths in
that diff are what the stage changed. Test paths are `*.spec.*`, `*.test.*`,
`*.e2e-spec.*`, `test/`, `tests/`, `__tests__/`, `e2e/`, `.maestro/`,
`cypress/`, `playwright/`, `playwright.config.*`.
- **Simplifier:** no test path may appear.
- **Tester / E2E Tester:** only test paths may appear. One exception: the
  E2E Tester may change `package.json`, the lockfile and `playwright.config.*`
  when `e2e-test-results.md` says it scaffolded the e2e setup.
- **Reviewer:** the diff must be empty.

A violation stops the run: show the stage and the offending paths, hand the
branch to the user — don't repair it yourself and don't continue.

## Stage 1 — Planner
Invoke the **planner** subagent (Agent tool, `subagent_type: planner`),
passing the feature description and the domain skill hint from Setup. Wait for
it to finish, then read `.pipeline/spec.md`.

**Gate:** if `## Open Questions` is anything other than `None`, STOP and show
the questions to the user. When the user answers, invoke the **planner** again
in **answers mode**, passing the questions and the answers verbatim; it records
them under `## Decisions`, sets Open Questions to `None` and adjusts only the
affected sections. Re-read the spec: still not `None` → ask again; `None` →
proceed. Never answer a question yourself and never edit the spec yourself —
the whole point of the Planner flagging ambiguity is that a human resolves it.

## Stage 2 — Coder
Invoke the **coder** subagent, passing the domain skill hint from Setup (e.g.
"load the `backend-nest` skill before implementing"). Wait, then read
`.pipeline/changes.md`.

**Gate:** `## Status` must be exactly `implemented`. Anything else (it stopped
on open questions or a broken spec) → STOP and report why to the user.

## Stage 2.5 — Simplifier
Invoke the **simplifier** subagent inside a **Scope check**. It loads the
Ponytail skill itself, simplifies only product code, verifies typecheck and
the existing tests still pass, and appends `## Ponytail` to
`.pipeline/changes.md`. No gate beyond the scope check — proceed to Stage 3.

## Stage 3 — Tester
Invoke the **tester** subagent (domain skill hint) inside a **Scope check**.
Wait, then read `.pipeline/test-results.md`.

**Gate** — proceed only when **all** of these hold:
- `## Status` is exactly `all passing`;
- every file under `## Tests added` has a `sim` row in `## Red check`;
- every row in `## Static checks` is exit `0` or `n/a — no script`.

`FAILURES` — or a `NÃO`/missing red-check row, or a non-zero static check
(treat both as FAILURES and say which) — enters the **Fix loop** below. Do
**not** fix the code yourself. `blocked: …` is the environment (database,
service, toolchain), not the code: show the reason and ask the user to fix it
and rerun this stage, or to stop the run here (Finish with no commit gate).

## Stage 3.5 — E2E Tester
Invoke the **e2e-tester** subagent inside a **Scope check**. It picks its own
mode from the spec and the diff — Playwright against the UI for frontend
changes, HTTP e2e tests against the running API for backend changes, both when
both surfaces changed, Maestro on the iPhone for React Native apps. Wait, then
read `.pipeline/e2e-test-results.md`.

**React Native app** (`react-native` in `package.json`) — before invoking, ask:
"Conecte e desbloqueie o iPhone no cabo (Modo Desenvolvedor ligado). Pronto?
(s = iPhone / n = simulador)" and pass `Target: iPhone` or `Target: simulator`
to the e2e-tester. Ask once per run; fix iterations reuse the answer.

In mobile mode the prints of every tested screen and of every failure are in
`.pipeline/review/` — always point the user there.

**Gate:** `all passing` → Stage 4. `n/a — no runtime surface to drive` →
Stage 4. `FAILURES` → **Fix loop**. `blocked: …` is the environment (device,
signing, toolchain, a non-local target), not the code — never send it to the
fix loop: show the reason and ask the user to fix it and rerun this stage, or
to go on to the Reviewer without E2E (the review and the PR body will say E2E
didn't run). Any other status is a failed stage (see **Stage failures**).

## Stage 4 — Reviewer
Invoke the **reviewer** subagent inside a **Scope check** (its diff must be
empty). It is read-only and returns the review content as its final message.
Write that content verbatim to `.pipeline/review.md` yourself (the reviewer
has no write tools, by design). If the verdict is not **SHIP**, enter the
**Fix loop** below with the review as the input.

## Fix loop — Planner-led, human-gated (at most 2 iterations)
Any failing stage feeds this loop: **Stage 3 FAILURES**, **Stage 3.5
FAILURES**, or a **Stage 4 non-SHIP verdict** (NEEDS WORK or BLOCK).

1. **Diagnose first.** `cp .pipeline/spec.md .pipeline/spec.before-fix.md`,
   then invoke the **planner** in **fix mode**, naming the failure report to
   read (`.pipeline/test-results.md`, `.pipeline/e2e-test-results.md`, or
   `.pipeline/review.md`) and the iteration number N. It appends
   `## Fix Plan (iteration N)` to the spec. Verify the contract above it is
   untouched:
   ```bash
   diff -B <(sed '/^## Fix Plan (iteration N)/,$d' .pipeline/spec.before-fix.md) <(sed '/^## Fix Plan (iteration N)/,$d' .pipeline/spec.md)
   ```
   must print nothing (`-B` ignores a blank line the Planner may leave before
   the heading). Otherwise STOP: the contract was rewritten during a fix
   — show the diff; a human decides, not the loop. If the Fix Plan's
   `### Open Questions` is anything other than `None`, ask the user and
   re-invoke the planner in answers mode, as in Stage 1, before going on.
2. **Human gate — always.** Show the failure report (the failing tests and
   output, or the review findings) **and** the Fix Plan (root cause, changes
   for the Coder, changes for the Tester / E2E), then ask: "Aplicar esta
   correção? (s/n)". The human decides here — including for BLOCK. On **n**,
   hand the branch to the user as-is and go to Finish. On **s**, run the
   iteration below — in this same pipeline run, never a fresh pipeline.
3. **Coder (fix mode)** — implements **Changes for the Coder** (it overwrites
   `## Status`). Gate as in Stage 2.
4. **Simplifier (fix mode)** — only the Fix Plan's files, inside a Scope check.
5. **Tester (fix mode)** — keeps its tests, applies **Changes for the Tester /
   E2E** if any, reruns. Gate as in Stage 3.
6. **E2E Tester (fix mode)** — same. Gate as in Stage 3.5.
7. **Reviewer** — re-run Stage 4.

Green Tester (`all passing` with the red check and static checks satisfied) +
green E2E (`all passing`, `n/a`, or a `blocked` the user chose to skip) +
**SHIP** → Finish. Otherwise you are back at step 1 with the new failure.

**Cap: at most 2 iterations.** Research on agent pipelines shows quality
converges in 1–2 iterations and degrades beyond that. After the second
iteration, stop offering the loop: hand the branch to the user with the last
failure report — a further fix is a human decision, not another automatic pass.

## Stage failures that aren't findings
A stage that ends without writing its handoff file, returns a partial result
(turn cap), or whose `## Status` / `## Verdict` you can't parse is a **failed
stage**, not a green one: show its final message and stop. Gates match
statuses **exactly** — an unknown status never passes.

## Finish
1. Present the final verdict (SHIP / NEEDS WORK / BLOCK) and a one-line summary
   of each stage's handoff file — including the red check and static checks
   outcome, and whether E2E ran.
2. **Commit gate — SHIP only.** Ask: "Commitar seguindo o gitflow? (s/n)". On
   NEEDS WORK / BLOCK don't offer it — unapproved code isn't committed by the
   pipeline. On **s**, invoke the **committer** subagent (commit mode), then
   read `.pipeline/commits.md`:
   - `needs author name` → the commit runs on the shared
     **AtomStudioFerramentas** account and no name is saved yet. Ask "Qual o
     seu nome para identificar os commits feitos pela conta
     AtomStudioFerramentas?" and invoke the committer again with
     `Author name: <nome>` (it saves it — asked only once per machine).
   - `stopped: …` → show the reason (a baseline overlap or a possible secret
     is the human's to untangle) and skip the PR gate.
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
