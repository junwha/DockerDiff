#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DDIFF_PY="$ROOT_DIR/ddiff.py"
TMP_DIR="$ROOT_DIR/test/.tmp/delete-mode"
REGISTRY_DIR="$TMP_DIR/registry"
BASE_DOCKERFILE="$TMP_DIR/Dockerfile.base"
DELTA_DOCKERFILE="$TMP_DIR/Dockerfile.delta"

PORT=5631
REGISTRY_CONTAINER="ddiff-delete-registry"
BASE_TAG="ddiff-delete/base:latest"
TARGET_TAG="ddiff-delete/delta:latest"
ARCHIVE_PATH="$ROOT_DIR/ddiff-delete--delta-latest.tar.gz"

log() {
  echo "[test-delete] $*"
}

wait_for_registry() {
  for _ in $(seq 1 30); do
    if curl -fsS "http://localhost:${PORT}/v2/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

manifest_exists() {
  local tag="$1"
  local repo="${tag%%:*}"
  local version="${tag##*:}"
  curl -fsS -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "http://localhost:${PORT}/v2/${repo}/manifests/${version}" >/dev/null
}

ensure_registry_image() {
  local wanted="registry:2.8.3"
  local candidate=""

  for ref in \
    "$wanted" \
    "docker.io/library/$wanted" \
    "docker.io/$wanted" \
    "localhost/$wanted"; do
    if podman image exists "$ref" >/dev/null 2>&1; then
      if [[ "$ref" != "$wanted" ]]; then
        podman tag "$ref" "$wanted" >/dev/null
      fi
      return 0
    fi
  done

  candidate="$(podman images --format '{{.Repository}}:{{.Tag}}' | awk '/(^|\/)registry:2\.8\.3$/ {print $1; exit}')"
  if [[ -n "$candidate" ]]; then
    podman tag "$candidate" "$wanted" >/dev/null
    return 0
  fi

  if ! podman pull docker.io/library/$wanted >/dev/null 2>&1; then
    log "SKIP: local image $wanted not found and pull is unavailable"
    exit 0
  fi
}

start_registry_or_skip() {
  local log_file="$TMP_DIR/registry-start.log"
  if ! DDIFF_FORCE_PODMAN=1 DDIFF_PORT="$PORT" DDIFF_CONTAINER_NAME="$REGISTRY_CONTAINER" DDIFF_REGISTRY_VOLUME="$REGISTRY_DIR" \
      python3 "$DDIFF_PY" server >"$log_file" 2>&1; then
    if rg -q "setns: IO error: Operation not permitted" "$log_file"; then
      log "SKIP: podman networking is not permitted in this environment"
      cat "$log_file"
      exit 0
    fi
    cat "$log_file"
    return 1
  fi
}

cleanup() {
  set +e
  podman rm -f "$REGISTRY_CONTAINER" >/dev/null 2>&1
  rm -rf "$TMP_DIR"
  rm -f "$ARCHIVE_PATH"
  podman rmi "$TARGET_TAG" >/dev/null 2>&1
  podman rmi "$BASE_TAG" >/dev/null 2>&1
  set -e
}

trap cleanup EXIT
cleanup
ensure_registry_image

mkdir -p "$TMP_DIR" "$REGISTRY_DIR"
cat > "$BASE_DOCKERFILE" <<'DOCKER'
FROM scratch
ADD base.txt /base.txt
DOCKER
cat > "$TMP_DIR/base.txt" <<'TXT'
base layer
TXT
cat > "$DELTA_DOCKERFILE" <<'DOCKER'
FROM ddiff-delete/base:latest
ADD hello_ddiff.txt /hello_ddiff.txt
DOCKER
cat > "$TMP_DIR/hello_ddiff.txt" <<'TXT'
hello delete mode
TXT

log "building local base and target images"
podman build -t "$BASE_TAG" -f "$BASE_DOCKERFILE" "$TMP_DIR" >/dev/null
podman build -t "$TARGET_TAG" -f "$DELTA_DOCKERFILE" "$TMP_DIR" >/dev/null

log "starting ddiff registry server with delete enabled"
start_registry_or_skip
wait_for_registry

log "creating diff archive from local images"
DDIFF_FORCE_PODMAN=1 DDIFF_PORT="$PORT" python3 - <<'PY'
import os, tarfile, shutil
import ddiff
base_tag = "ddiff-delete/base:latest"
target_tag = "ddiff-delete/delta:latest"

ddiff.push_images([base_tag])
ddiff.push_images([target_tag])

base_tag = ddiff._prepare_tag(base_tag)
target_tag = ddiff._prepare_tag(target_tag)
target_repo = target_tag.split(":")[0]

output_dir = os.path.join(os.getcwd(), ".ddiff-image")
shutil.rmtree(output_dir, ignore_errors=True)
blob_dir = os.path.join(output_dir, "blobs")
os.makedirs(blob_dir)

base_manifest, _ = ddiff._request_manifest(base_tag)
target_manifest, target_manifest_media_type = ddiff._request_manifest(target_tag)
base_blobs = ddiff._parse_blob_list(base_manifest)
target_blobs = ddiff._parse_blob_list(target_manifest)
diff_blobs = set(target_blobs) - set(base_blobs)

for digest in diff_blobs:
    ddiff._download_blob(target_repo, digest, blob_dir)

with open(output_dir + "/manifest.json", "w") as f:
    f.write(target_manifest)
with open(os.path.join(output_dir, "MANIFEST_MEDIA_TYPE"), "w") as f:
    f.write(target_manifest_media_type)
with open(os.path.join(output_dir, "BASE"), "w") as f:
    f.write(base_tag)
with open(os.path.join(output_dir, "TARGET"), "w") as f:
    f.write(target_tag)
with open(os.path.join(output_dir, "MOUNT_BLOBS"), "w") as f:
    f.write("|".join(list(set(target_blobs) - diff_blobs)))
with open(os.path.join(output_dir, "UPLOAD_BLOBS"), "w") as f:
    f.write("|".join(diff_blobs))

archive_name = f"{target_tag.replace('/', '--').replace(':', '-')}.tar.gz"
with tarfile.open(archive_name, "w:gz") as tar:
    tar.add(output_dir, arcname=".ddiff-image")
shutil.rmtree(output_dir)
PY
[[ -f "$ARCHIVE_PATH" ]]

log "explicit delete command removes pushed target"
DDIFF_FORCE_PODMAN=1 DDIFF_PORT="$PORT" DDIFF_CONTAINER_NAME="$REGISTRY_CONTAINER" \
  python3 "$DDIFF_PY" delete "$TARGET_TAG" >/dev/null
if manifest_exists "$TARGET_TAG"; then
  echo "manifest still exists after ddiff delete"
  exit 1
fi

log "restart with clean registry data for load --delete scenario"
podman rm -f "$REGISTRY_CONTAINER" >/dev/null
rm -rf "$REGISTRY_DIR"
mkdir -p "$REGISTRY_DIR"
start_registry_or_skip
wait_for_registry

log "load archive and delete from registry in one step"
DDIFF_FORCE_PODMAN=1 DDIFF_PORT="$PORT" DDIFF_CONTAINER_NAME="$REGISTRY_CONTAINER" \
  python3 "$DDIFF_PY" load "$BASE_TAG" "$ARCHIVE_PATH" --delete >/dev/null

log "verify image loaded on host"
podman run --rm "$TARGET_TAG" cat /hello_ddiff.txt | grep -q 'hello delete mode'

log "verify manifest no longer exists after load --delete"
if manifest_exists "$TARGET_TAG"; then
  echo "manifest still exists after ddiff load --delete"
  exit 1
fi

log "PASS"
