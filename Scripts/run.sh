#!/bin/bash
set -euo pipefail
umask 077
app="$HOME/Applications/AXTestTools/AXRunner.app"
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo 'Usage: bash Scripts/run.sh --preflight | --check /absolute/scenario.json | --scenario /absolute/scenario.json'
  echo 'An isolated result directory is created for every run; report exitCode is propagated.'
  exit 0
fi
case "$1" in
  --preflight) [[ $# -eq 1 ]] || exit 64 ;;
  --check|--scenario) [[ $# -eq 2 && "$2" == /* ]] || exit 64 ;;
  *) exit 64 ;;
esac
[[ -d "$app" ]] || { echo 'Install AXRunner first.' >&2; exit 69; }
result_dir="$(mktemp -d "${TMPDIR:-/tmp}/ax-test-result.XXXXXX")"
result="$result_dir/report.json"
/usr/bin/open -g -W -n "$app" --args "$@" --result "$result"
# LaunchServices can return before a short-lived app becomes waitable.
# Wait for a complete JSON report, never interpret launch success as test success.
deadline=$((SECONDS + 150))
while :; do
  if [[ -f "$result" && ! -L "$result" ]] && code="$(/usr/bin/plutil -extract exitCode raw -o - "$result" 2>/dev/null)"; then
    break
  fi
  if (( SECONDS >= deadline )); then echo "Missing or incomplete report: $result" >&2; exit 74; fi
  /bin/sleep 0.1
done
/bin/cat "$result"
echo
echo "Report: $result"
case "$code" in 0|1|2|3|74|77) exit "$code" ;; *) echo 'Invalid report exit code.' >&2; exit 74 ;; esac
