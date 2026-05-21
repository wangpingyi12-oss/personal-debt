#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-personal-debt.xcodeproj}"
SCHEME="${SCHEME:-personal-debt}"
CONFIGURATION="${CONFIGURATION:-Debug}"
RELEASE_CONFIGURATION="${RELEASE_CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 14 Plus,OS=18.0}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-95}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/DerivedData/Preflight}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_BUNDLE="${RESULT_BUNDLE:-$DERIVED_DATA/Test-${SCHEME}-iPhone14-${TIMESTAMP}.xcresult}"
TEST_LOG="$DERIVED_DATA/test-${TIMESTAMP}.log"
BUILD_LOG="$DERIVED_DATA/release-build-${TIMESTAMP}.log"
COVERAGE_JSON="$DERIVED_DATA/coverage-${TIMESTAMP}.json"

mkdir -p "$DERIVED_DATA"

echo "==> Booting simulator: iPhone 14 Plus"
xcrun simctl boot "iPhone 14 Plus" >/dev/null 2>&1 || true
xcrun simctl bootstatus "iPhone 14 Plus" -b

echo "==> Running full tests with coverage"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  clean test | tee "$TEST_LOG"

echo "==> Building Release configuration"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$RELEASE_CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build | tee "$BUILD_LOG"

echo "==> Checking changed app source coverage"
xcrun xccov view --report --json "$RESULT_BUNDLE" > "$COVERAGE_JSON"

python3 - "$ROOT_DIR" "$RESULT_BUNDLE" "$COVERAGE_THRESHOLD" <<'PY'
import json
import os
import re
import subprocess
import sys

root_dir, result_bundle, threshold_text = sys.argv[1:4]
threshold = float(threshold_text)

def run(*args: str) -> str:
    return subprocess.check_output(args, cwd=root_dir, text=True)

def app_swift_path(path: str) -> bool:
    return (
        path.startswith("personal-debt/")
        and path.endswith(".swift")
        and not path.startswith("personal-debtTests/")
        and not path.startswith("personal-debtUITests/")
    )

def changed_paths() -> list[str]:
    status = run("git", "status", "--porcelain").splitlines()
    paths: list[str] = []

    for line in status:
        if not line:
            continue

        code = line[:2]
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]

        if code.strip() == "D" or "D" in code:
            continue
        if app_swift_path(path):
            paths.append(path)

    return sorted(set(paths))

def changed_lines_for(path: str) -> set[int]:
    if run("git", "ls-files", "--others", "--exclude-standard", "--", path).strip():
        with open(os.path.join(root_dir, path), "r", encoding="utf-8") as handle:
            return set(range(1, sum(1 for _ in handle) + 1))

    diff = run("git", "diff", "--unified=0", "--no-ext-diff", "--", path)
    lines: set[int] = set()

    for match in re.finditer(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff):
        start = int(match.group(1))
        count = int(match.group(2) or "1")
        if count > 0:
            lines.update(range(start, start + count))

    return lines

def coverage_lines_for(path: str) -> dict[int, dict]:
    absolute_path = os.path.join(root_dir, path)
    raw = run(
        "xcrun",
        "xccov",
        "view",
        "--archive",
        "--file",
        absolute_path,
        "--json",
        result_bundle,
    )
    coverage_by_file = json.loads(raw)
    return {
        int(item["line"]): item
        for items in coverage_by_file.values()
        for item in items
    }

tracked_paths = changed_paths()
total_executable = 0
total_covered = 0
uncovered: list[str] = []

for path in tracked_paths:
    changed_lines = changed_lines_for(path)
    if not changed_lines:
        continue

    coverage_lines = coverage_lines_for(path)
    for line in sorted(changed_lines):
        coverage = coverage_lines.get(line)
        if not coverage or not coverage.get("isExecutable"):
            continue

        total_executable += 1
        if int(coverage.get("executionCount", 0)) > 0:
            total_covered += 1
        else:
            uncovered.append(f"{path}:{line}")

if total_executable == 0:
    print("No executable app Swift lines changed.")
    raise SystemExit(0)

coverage = total_covered / total_executable * 100

print(f"Changed executable lines: {total_executable}")
print(f"Covered changed lines: {total_covered}")
print(f"Changed-line coverage: {coverage:.2f}%")
print(f"Required coverage: {threshold:.2f}%")

if uncovered:
    print("Uncovered changed executable lines:")
    for item in uncovered[:50]:
        print(f"  {item}")
    if len(uncovered) > 50:
        print(f"  ... and {len(uncovered) - 50} more")

if coverage + 1e-9 < threshold:
    raise SystemExit(f"Changed-line coverage check failed: {coverage:.2f}% < {threshold:.2f}%")
PY

echo "==> Preflight passed"
echo "Result bundle: $RESULT_BUNDLE"
echo "Test log: $TEST_LOG"
echo "Release build log: $BUILD_LOG"
