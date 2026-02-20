#!/usr/bin/env bash
set -euo pipefail

# Integration tests for ddiff backend modes.
#
# Common lifecycle validated by every mode:
#   1) build base/delta test images
#   2) run `ddiff diff` against a first registry
#   3) remove that registry and delete its data
#   4) run `ddiff load` against a fresh registry
#   5) verify the loaded image contains tmux
#   6) clean all containers/images/archive/tmp files

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$ROOT_DIR/test"
DOCKERFILES_DIR="$TEST_DIR/dockerfiles"
DDIFF_PY="$ROOT_DIR/ddiff.py"

BASE_TAG="ddiff-test/base:latest"
DELTA_TAG="ddiff-test/delta:latest"
ARCHIVE_NAME="ddiff-test--delta-latest.tar.gz"
ARCHIVE_PATH="$ROOT_DIR/$ARCHIVE_NAME"
REGISTRY_IMAGE="registry:2.8.3"
TMP_ROOT="$TEST_DIR/.tmp/ddiff-backends"

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

log() {
  echo "[test] $*"
}

# Run one command, stream its captured output, and return exact exit code.
run_step() {
  local logfile="$1"
  shift

  mkdir -p "$(dirname "$logfile")"
  {
    echo "+ $*"
    "$@"
  } >"$logfile" 2>&1
  local status=$?

  cat "$logfile"
  return "$status"
}

# Wait for Docker Registry HTTP API to become ready.
wait_for_registry() {
  local port="$1"
  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${port}/v2/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Print missing tools and return non-zero if any required command is absent.
have_all_commands() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[SKIP] missing command: $cmd"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

# Best-effort cleanup for a single test case.
cleanup_case() {
  local runtime="$1"
  local diff_container="$2"
  local load_container="$3"
  local work_dir="$4"

  set +e
  "$runtime" rm -f "$diff_container" >/dev/null 2>&1
  "$runtime" rm -f "$load_container" >/dev/null 2>&1
  "$runtime" rmi "$DELTA_TAG" >/dev/null 2>&1
  "$runtime" rmi "$BASE_TAG" >/dev/null 2>&1
  rm -f "$ARCHIVE_PATH"
  rm -rf "$work_dir"
  set -e
}

# Generic mode runner.
#
# Injected behavior per mode:
# - runtime: docker or podman
# - force_key/force_value: optional env injection (DDIFF_FORCE_*)
# - expect_marker: optional log marker that confirms mode selection
# - required tools: mode-specific prerequisites
run_case() {
  local name="$1"
  local runtime="$2"
  local force_key="$3"
  local force_value="$4"
  local expect_marker="$5"
  local diff_port="$6"
  local load_port="$7"
  shift 7
  local -a required=("$@")

  TOTAL=$((TOTAL + 1))

  local work_dir="$TMP_ROOT/$name"
  local logs_dir="$work_dir/logs"
  local diff_registry_dir="$work_dir/registry_diff"
  local load_registry_dir="$work_dir/registry_load"
  local diff_container="ddiff-${name}-diff"
  local load_container="ddiff-${name}-load"

  rm -rf "$work_dir"
  mkdir -p "$logs_dir" "$diff_registry_dir" "$load_registry_dir"

  log "[$name] prerequisites"
  if ! have_all_commands "${required[@]}"; then
    SKIPPED=$((SKIPPED + 1))
    echo "SKIP: $name"
    cleanup_case "$runtime" "$diff_container" "$load_container" "$work_dir"
    return 0
  fi

  local status=0

  log "[$name] build base image"
  run_step "$logs_dir/build-base.log" \
    "$runtime" build -t "$BASE_TAG" -f "$DOCKERFILES_DIR/Dockerfile.base" "$TEST_DIR" || status=$?

  if [[ "$status" -eq 0 ]]; then
    log "[$name] build delta image"
    run_step "$logs_dir/build-delta.log" \
      "$runtime" build -t "$DELTA_TAG" -f "$DOCKERFILES_DIR/Dockerfile.delta" "$TEST_DIR" || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    log "[$name] start diff registry"
    run_step "$logs_dir/registry-diff-start.log" \
      "$runtime" run -d --name "$diff_container" -p "${diff_port}:5000" -v "$diff_registry_dir:/var/lib/registry" "$REGISTRY_IMAGE" || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    wait_for_registry "$diff_port" || { echo "registry not ready on ${diff_port}" | tee "$logs_dir/registry-diff-ready.log"; status=1; }
  fi

  if [[ "$status" -eq 0 ]]; then
    log "[$name] ddiff diff"
    if [[ -n "$force_key" ]]; then
      run_step "$logs_dir/ddiff-diff.log" \
        env DDIFF_URL="http://127.0.0.1:${diff_port}" "$force_key=$force_value" \
        python3 "$DDIFF_PY" diff "$BASE_TAG" "$DELTA_TAG" || status=$?
    else
      run_step "$logs_dir/ddiff-diff.log" \
        env DDIFF_URL="http://127.0.0.1:${diff_port}" \
        python3 "$DDIFF_PY" diff "$BASE_TAG" "$DELTA_TAG" || status=$?
    fi
  fi

  if [[ "$status" -eq 0 && ! -f "$ARCHIVE_PATH" ]]; then
    echo "missing archive: $ARCHIVE_PATH" | tee "$logs_dir/archive-check.log"
    status=1
  fi

  if [[ "$status" -eq 0 ]]; then
    log "[$name] delete diff registry and data"
    "$runtime" rm -f "$diff_container" >/dev/null 2>&1 || true
    rm -rf "$diff_registry_dir"
    mkdir -p "$diff_registry_dir"

    log "[$name] start fresh load registry"
    run_step "$logs_dir/registry-load-start.log" \
      "$runtime" run -d --name "$load_container" -p "${load_port}:5000" -v "$load_registry_dir:/var/lib/registry" "$REGISTRY_IMAGE" || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    wait_for_registry "$load_port" || { echo "registry not ready on ${load_port}" | tee "$logs_dir/registry-load-ready.log"; status=1; }
  fi

  if [[ "$status" -eq 0 ]]; then
    log "[$name] ddiff load"
    if [[ -n "$force_key" ]]; then
      run_step "$logs_dir/ddiff-load.log" \
        env DDIFF_URL="http://127.0.0.1:${load_port}" "$force_key=$force_value" \
        python3 "$DDIFF_PY" load "$ARCHIVE_PATH" || status=$?
    else
      run_step "$logs_dir/ddiff-load.log" \
        env DDIFF_URL="http://127.0.0.1:${load_port}" \
        python3 "$DDIFF_PY" load "$ARCHIVE_PATH" || status=$?
    fi
  fi

  if [[ "$status" -eq 0 && -n "$expect_marker" ]]; then
    if ! grep -q "$expect_marker" "$logs_dir/ddiff-diff.log"; then
      echo "missing mode marker: $expect_marker" | tee "$logs_dir/mode-check.log"
      status=1
    fi
  fi

  if [[ "$status" -eq 0 ]]; then
    log "[$name] verify loaded image"
    run_step "$logs_dir/verify.log" "$runtime" run --rm "$DELTA_TAG" tmux -V || status=$?
  fi

  cleanup_case "$runtime" "$diff_container" "$load_container" "$work_dir"

  if [[ "$status" -eq 0 ]]; then
    PASSED=$((PASSED + 1))
    echo "PASS: $name"
  else
    FAILED=$((FAILED + 1))
    echo "FAIL: $name"
  fi
}

# Test 1: docker mode
# Inject: no force flags
# Expect: default docker path succeeds end-to-end
run_docker_mode() {
  run_case \
    "docker" \
    "docker" \
    "" "" "" \
    5601 5602 \
    python3 curl docker
}

# Test 2: docker-skopeo mode
# Inject: DDIFF_FORCE_SKOPEO=1
# Expect: ddiff log contains "DDIFF_FORCE_SKOPEO is enabled"
run_docker_skopeo_mode() {
  run_case \
    "docker-skopeo" \
    "docker" \
    "DDIFF_FORCE_SKOPEO" "1" "DDIFF_FORCE_SKOPEO is enabled" \
    5611 5612 \
    python3 curl docker skopeo
}

# Test 3: podman mode
# Inject: DDIFF_FORCE_PODMAN=1
# Expect: ddiff log contains "DDIFF_FORCE_PODMAN is enabled"
run_podman_mode() {
  run_case \
    "podman" \
    "podman" \
    "DDIFF_FORCE_PODMAN" "1" "DDIFF_FORCE_PODMAN is enabled" \
    5621 5622 \
    python3 curl podman skopeo
}

run_selected_cases() {
  local target="$1"
  case "$target" in
    all|docker|docker-skopeo|podman) ;;
    *)
      echo "Usage: $0 [all|docker|docker-skopeo|podman]"
      exit 2
      ;;
  esac

  [[ "$target" == "all" || "$target" == "docker" ]] && run_docker_mode
  [[ "$target" == "all" || "$target" == "docker-skopeo" ]] && run_docker_skopeo_mode
  [[ "$target" == "all" || "$target" == "podman" ]] && run_podman_mode
}

main() {
  mkdir -p "$TMP_ROOT"
  run_selected_cases "${1:-all}"

  echo ""
  echo "Total: $TOTAL, Passed: $PASSED, Failed: $FAILED, Skipped: $SKIPPED"

  [[ "$FAILED" -eq 0 ]]
}

main "$@"
