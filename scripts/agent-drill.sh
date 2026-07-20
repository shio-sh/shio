#!/bin/bash
# agent-drill.sh — a deterministic fake agent for supervision testing.
#
# The real trigger ("a coding agent happens to block on y/n") can't be produced
# on demand, which makes the supervision loop feel untestable. This script IS
# the trigger: run it inside any Shio repo terminal on the Mac (those are
# `shio-<repo>` tmux sessions — exactly what the watcher polls) and it walks
# the classifier's states on cue:
#
#   running (spinner + "esc to interrupt") → waiting (y/n prompt) → answered
#
# What each mode proves:
#   default        the full loop: ⚑ appears in Shio within ~4s, the phone
#                  banners, lock-screen Approve lands back here as a real
#                  keystroke — and the script REPORTS what it received, plus
#                  whether a duplicate keystroke arrived (the at-most-once
#                  guard's failure mode, e.g. answering from two devices or
#                  keyboard + phone in the same window).
#   --menu         same, with Claude Code's numbered-menu prompt style.
#   --tease        prints prompt-LIKE text while visibly running, then never
#                  prompts. The phone must stay silent — this is the
#                  false-ping bias test. A banner here is a regression.
#
# Usage:
#   ./scripts/agent-drill.sh              # one round (8s running, then prompt)
#   ./scripts/agent-drill.sh -n 3         # three rounds back to back
#   ./scripts/agent-drill.sh -r 20        # longer running phase (seconds)
#   ./scripts/agent-drill.sh --menu | --tease
#
# No repo handy? A standalone session works for the push loop too (any
# `shio-*` tmux session is watched):
#   tmux new-session -s shio-drill "$PWD/scripts/agent-drill.sh"

ROUNDS=1 RUNSECS=8 MODE=prompt
while [ $# -gt 0 ]; do
  case "$1" in
    -n) ROUNDS="$2"; shift 2 ;;
    -r) RUNSECS="$2"; shift 2 ;;
    --menu) MODE=menu; shift ;;
    --tease) MODE=tease; shift ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# "claude code" in the banner makes the detector name the agent, so pushes
# read exactly like the real thing ("Claude Code needs you").
echo "shio agent drill · impersonating claude code for supervision testing"

for round in $(seq 1 "$ROUNDS"); do
  echo
  echo "── round $round/$ROUNDS · running phase (${RUNSECS}s) ──"
  i=0
  while [ "$i" -lt "$RUNSECS" ]; do
    f=${FRAMES:$((i % 10)):1}
    printf '\r%s working… (esc to interrupt) %2ds' "$f" "$i"
    if [ "$MODE" = tease ] && [ "$i" -eq 3 ]; then
      printf '\nlog: docs mention answering (y/n) at a prompt — displayed content, not a prompt\n'
    fi
    sleep 1
    i=$((i + 1))
  done

  # Overwrite the spinner line (the Mac watcher reads the RENDERED pane via
  # capture-pane) and follow with a summary block long enough to push the
  # running markers out of the classifier's live window on the raw-stream
  # side too (an open phone session ingests the stream, not the pane).
  printf '\r✓ run phase complete — %s seconds of pretend work            \n' "$RUNSECS"
  cat <<'EOF'
  wrote 3 files · 120 insertions · 14 deletions
  checks: fmt ok · lint ok · types ok · unit tests passed
  staged the migration plan; nothing has been applied yet.
  the next step would change the database schema.
EOF

  if [ "$MODE" = tease ]; then
    # Scroll the tease line's "(y/n)" safely out of the classifier's window
    # with quiet filler, then end the round WITHOUT prompting.
    for n in 1 2 3 4; do
      echo "  log: replayed transcript block $n of 4 · no user input was requested"
    done
    echo "tease round done — if the phone pinged during this round, the false-waiting bias regressed."
    continue
  fi

  if [ "$MODE" = menu ]; then
    echo "Apply the schema migration?"
    echo "❯ 1. yes"
    echo "  2. no"
  else
    echo "Do you want to proceed? (y/n)"
  fi
  start=$(date +%s)
  read -r answer
  took=$(( $(date +%s) - start ))
  echo "received: '${answer}' after ${took}s"

  # The at-most-once window. A SECOND keystroke arriving now means the
  # dedupe / still-waiting guard failed (two devices answering, keyboard +
  # phone racing, or a stale Action replayed). 10s covers the watcher's
  # next two polls.
  if read -r -t 10 dup; then
    echo "⚠ DUPLICATE INJECTION — also received '${dup}'. The at-most-once guard failed; file it."
  else
    echo "✓ no duplicate keystroke within 10s"
  fi
done

echo
echo "drill complete — back at the shell."
