#!/bin/sh
# Only the unhosted CommandRunner tests invoke this fixture. Scratch signaling
# lets teardown stop its own descendants without searching for or killing PIDs.
set -eu

case "$1" in
  streams)
    (printf 'stdout\n'; /bin/dd if=/dev/zero bs=65536 count=32 2>/dev/null) &
    (printf 'stderr\n'; /bin/dd if=/dev/zero bs=65536 count=32 2>/dev/null) >&2 &
    wait
    ;;
  nonzero)
    printf 'out\n'
    printf 'failure detail\n' >&2
    exit 23
    ;;
  signal)
    printf 'signal detail\n' >&2
    kill -TERM "$$"
    ;;
  hang)
    printf 'ready\n'
    printf 'ready\n' >"$2/ready"
    exec /bin/sleep 10
    ;;
  inherited-writer|ignore-term)
    mode=$1
    scratch=$2
    wait_for_teardown() {
      # Self-expire even if a test aborts before requesting teardown.
      iteration=0
      while [ ! -f "$scratch/stop" ] && [ "$iteration" -lt 250 ]; do
        /bin/sleep 0.02
        iteration=$((iteration + 1))
      done
      printf 'done\n' >"$scratch/done"
    }
    if [ "$mode" = inherited-writer ]; then
      wait_for_teardown &
      printf 'ready\n' >"$scratch/ready"
      exit 0
    else
      trap '' TERM
      printf 'ready\n' >"$scratch/ready"
      wait_for_teardown
    fi
    ;;
  *) exit 64 ;;
esac
