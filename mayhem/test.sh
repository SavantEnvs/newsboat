#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# newsboat ships two assertion suites, both pre-built by build.sh (`make test`): the Catch2 binary
# test/test (C++) and the cargo workspace test binaries (Rust). Counts come from each framework's own
# summary line; a missing/neutered runner prints no summary, so nothing matches and we fail loudly.
export TERM=xterm   # stfl/ncurses tests abort with 'Error opening terminal: unknown' otherwise
export LC_ALL=C.UTF-8   # the UTF-8 wrapping/entity/strwidth tests need a UTF-8 locale
passed=0; failed=0; skipped=0; ok_cpp=0; ok_rs=0

cpp_out=$(cd test && ./test 2>&1); cpp_rc=$?
printf '%s\n' "$cpp_out" | tail -5
if m=$(printf '%s\n' "$cpp_out" | grep -Eo 'All tests passed \([0-9]+ assertions? in [0-9]+ test cases?\)' | tail -1) && [ -n "$m" ]; then
  n=$(printf '%s' "$m" | grep -Eo 'in [0-9]+ test case' | grep -Eo '[0-9]+')
  passed=$((passed + n)); ok_cpp=1
elif m=$(printf '%s\n' "$cpp_out" | grep -E '^test cases: +[0-9]+ \|' | tail -1) && [ -n "$m" ]; then
  p=$(printf '%s' "$m" | grep -Eo '[0-9]+ passed' | grep -Eo '[0-9]+' || echo 0)
  f=$(printf '%s' "$m" | grep -Eo '[0-9]+ failed( as expected)?' | grep -Eo '^[0-9]+' || echo 0)
  passed=$((passed + ${p:-0})); failed=$((failed + ${f:-0})); ok_cpp=1
fi
[ "$cpp_rc" -eq 0 ] || failed=$((failed + 1))

rs_out=$(cargo test --workspace --exclude libnewsboat-ffi --no-fail-fast 2>&1); rs_rc=$?
printf '%s\n' "$rs_out" | grep -E '^test result:'
while read -r p f i; do
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + i)); ok_rs=1
done < <(printf '%s\n' "$rs_out" | sed -nE 's/^test result: [a-zA-Z]+\. ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored.*/\1 \2 \3/p')
[ "$rs_rc" -eq 0 ] || failed=$((failed + 1))

if [ "$ok_cpp" -ne 1 ] || [ "$ok_rs" -ne 1 ] || [ "$passed" -lt 100 ]; then
  echo "test.sh: missing or implausible test summary (cpp=$ok_cpp rust=$ok_rs passed=$passed)" >&2
  failed=$((failed + 1))
fi
emit_ctrf "catch2+cargo-test" "$passed" "$failed" "$skipped"
