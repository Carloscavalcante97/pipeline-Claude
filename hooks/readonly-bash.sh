#!/bin/bash
# PreToolUse(Bash) hook for the pipeline's read-only stages (Planner, Reviewer).
# Installed at ~/.claude/hooks/pipeline/readonly-bash.sh.
#
# Allows read-only commands only: no redirection to a file, no in-place
# editors, no git that changes state, no interpreters or package scripts.
# Exit 2 blocks the call; stderr is shown to the agent as the reason.
cmd=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null) \
  || { echo "pipeline: read-only stage — could not parse the command, blocked" >&2; exit 2; }

deny() { echo "pipeline: read-only stage — blocked: $1. Allowed: git diff/status/log/show, ls, cat, grep, find, head, tail, wc and other read-only commands." >&2; exit 2; }

# Redirection to a file (2>&1 and /dev/null are fine).
stripped=$(printf '%s' "$cmd" | sed -E 's#[0-9]*>&[0-9]##g; s#[0-9]*>+ */dev/null##g')
case "$stripped" in *">"*) deny "redirection to a file" ;; esac

# Every segment (split on | && || ; newline, $( and backticks) must start with
# a read-only command. Shell keywords and env assignments are skipped.
segments=$(printf '%s\n' "$cmd" | sed -E 's/\|\||&&|;|\||\$\(|`/\n/g')
while IFS= read -r seg; do
  set -- $seg
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*|do|then|else|elif|if|while|until|time|xargs|env|'!'|'{'|'('|')') shift; continue ;;
    esac
    break
  done
  [ $# -eq 0 ] && continue
  case "$1" in
    for|done|fi|esac|'}'|:|cd|ls|cat|head|tail|wc|grep|rg|awk|cut|sort|uniq|tr|echo|printf|pwd|which|type|file|stat|diff|tree|basename|dirname|realpath|test|'['|true|false|jq|date|shasum|md5|read|exit|return) ;;
    find)
      case "$seg" in *" -delete"*|*" -exec"*|*" -ok"*) deny "find with -delete/-exec" ;; esac ;;
    sed)
      case "$seg" in *" -i"*|*" --in-place"*) deny "sed -i" ;; esac ;;
    git)
      case "$2" in
        diff|status|log|show|ls-files|rev-parse|blame|grep|cat-file|describe|shortlog|merge-base|remote|worktree) ;;
        *) deny "git $2" ;;
      esac
      case "$2:$3" in remote:add|remote:remove|remote:rm|remote:set-url|remote:rename|remote:prune) deny "git remote $3" ;; esac
      case "$2:$3" in worktree:list) ;; worktree:*) deny "git worktree $3" ;; esac ;;
    node) case "$2" in -v|--version) ;; *) deny "node" ;; esac ;;
    npm)  case "$2" in ls|list|view|-v|--version) ;; *) deny "npm $2" ;; esac ;;
    *) deny "$1" ;;
  esac
done <<< "$segments"
exit 0
