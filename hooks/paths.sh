#!/bin/bash
# PreToolUse(Edit|Write) hook for the pipeline's subagents. Installed at
# ~/.claude/hooks/pipeline/paths.sh and referenced from the agents' frontmatter.
#
#   paths.sh tests-only   Tester / E2E Tester: only test files and .pipeline/
#   paths.sh no-tests     Coder / Simplifier: anything except test files
#
# Exit 2 blocks the call; stderr is shown to the agent as the reason.
mode="$1"
path=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
[ -z "$path" ] && exit 0

case "$path" in
  */.pipeline/*) exit 0 ;;
esac

is_test=0
case "$path" in
  *.spec.*|*.test.*|*.e2e-spec.*|*.cy.*|*/test/*|*/tests/*|*/__tests__/*|*/e2e/*|*/.maestro/*|*/cypress/*|*/playwright/*|*/playwright.config.*) is_test=1 ;;
esac

if [ "$mode" = tests-only ] && [ "$is_test" = 0 ]; then
  echo "pipeline: this stage only edits test files and .pipeline/ — $path stays as it is. A failure is a finding for the report, not something to fix here." >&2
  exit 2
fi
if [ "$mode" = no-tests ] && [ "$is_test" = 1 ]; then
  echo "pipeline: this stage doesn't edit tests ($path) — tests belong to the Tester. If an existing test must change, say so in changes.md." >&2
  exit 2
fi
exit 0
