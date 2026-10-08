#!/usr/bin/env bash
#
# Per-file line-coverage gate for `cli/lib`.
#
# Expects `dart test --coverage=coverage` to have already run in `cli/`.
# Converts the raw VM coverage into an lcov report and fails unless EVERY
# non-excluded file is at or above the threshold (default 85%).
#
# Shared by .githooks/pre-push and .github/workflows/cli-checks.yml so the
# local and CI gates cannot drift apart.
#
#   COVERAGE_MIN=90 cli/tool/coverage_gate.sh
#
set -euo pipefail

COVERAGE_MIN="${COVERAGE_MIN:-85}"
# Pinned so a new `coverage` release cannot change the gate unannounced.
COVERAGE_PKG_VERSION="1.15.1"

# A non-numeric threshold (e.g. "85%") would make awk compare strings and let
# low coverage pass, so reject it up front.
if ! [[ "$COVERAGE_MIN" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "coverage-gate: COVERAGE_MIN must be a number (got '$COVERAGE_MIN')." >&2
  exit 2
fi

# Resolve cli/ from the script's own location so it works from any CWD.
CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CLI_DIR"

if [ ! -d coverage ]; then
  echo "coverage-gate: no ./coverage directory — run 'dart test --coverage=coverage' first." >&2
  exit 1
fi

# `format_coverage` ships with the `coverage` package; activating the pinned
# version is idempotent, so the gate is self-contained on a fresh machine or
# CI runner.
dart pub global activate coverage "$COVERAGE_PKG_VERSION" >/dev/null

# `--check-ignore` makes format_coverage honor `// coverage:ignore-file`
# comments, so explicitly excluded files never enter the report.
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib \
  --check-ignore \
  --packages=.dart_tool/package_config.json >/dev/null

if [ ! -s coverage/lcov.info ]; then
  echo "coverage-gate: no coverage data produced." >&2
  exit 1
fi

# Enforce the threshold PER FILE. Walk each SF:…end_of_record block and
# collect every file whose line coverage is below COVERAGE_MIN. A file with
# `// coverage:ignore-file` produces no SF: block (thanks to --check-ignore),
# so it is excluded automatically. Files never imported by any test also
# produce no block — every testable file must be imported by ≥1 test to count.
BELOW=$(awk -F: '
  /^SF:/           { file=$2; lf=0; lh=0 }
  /^LF:/           { lf=$2 }
  /^LH:/           { lh=$2 }
  /^end_of_record/ {
    pct = lf > 0 ? lh / lf * 100 : 100
    if (pct < MIN) { printf "  %6.2f%%  %s\n", pct, file }
  }
' MIN="$COVERAGE_MIN" coverage/lcov.info)

if [ -n "$BELOW" ]; then
  echo "" >&2
  echo "❌ coverage-gate: the following files are below the required ${COVERAGE_MIN}%:" >&2
  echo "$BELOW" >&2
  echo "" >&2
  echo "   Add tests or mark the file '// coverage:ignore-file'." >&2
  exit 1
fi

echo "✅ coverage-gate: per-file coverage gate passed (every file ≥ ${COVERAGE_MIN}%)."
