#!/usr/bin/env python3
# registry_seed_parallel.py
# Build a registry:2.8.3-compatible on-disk store directly from a list of Docker Hub images.
# Parallel, image-by-image processing with best-effort deduplication.
#
# Input: a text file with one "repo[:tag]" per line (e.g., swebench/foo:latest)
# Output: directory you can mount as /var/lib/registry for registry:2.8.3
#
# What it does (per image, in parallel):
# 1) Resolve manifest (if index, pick linux/amd64)
# 2) Compute manifest blob digest = sha256(manifest_bytes)
# 3) For each required blob (manifest-as-blob, config, layers):
#    - If target path already exists, skip
#    - Otherwise download (streamed, sha256-verified)
# 4) Populate registry filesystem links for the repo:tag
#
# Notes:
# - Optional Docker Hub token is used to mitigate rate limits (public pulls).
# - Parallelism is per image, not per blob (simpler dedup; avoids global gather).
# - Uses best-effort in-memory dedup across threads; file existence checks remain the source of truth.
# - Only linux/amd64 is selected from manifest lists.
# - This script does NOT run the registry; it only prepares the data dir.

import os
import json
import argparse
import hashlib
import time
import threading
from typing import Tuple, Dict, List, Optional
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed

SRC_REG = "https://registry-1.docker.io"
ACCEPT = ",".join([
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
])

# --------- globals for best-effort cross-thread dedup ---------
DOWNLOADED = set()          # set of digests (e.g., "sha256:...") known to be downloaded this run
DOWNLOADED_LOCK = threading.Lock()

# Thread-local session holder
TLS = threading.local()

# ---------- FS helpers ----------
def ensure(path: str):
    os.makedirs(path, exist_ok=True)

def blob_file_path(root: str, digest: str) -> str:
    algo, hexd = digest.split(":", 1)
    return os.path.join(root, "docker", "registry", "v2", "blobs", algo, hexd[:2], hexd, "data")

def write_link(path: str, digest: str):
    ensure(os.path.dirname(path))
    with open(path, "w", encoding="utf-8") as f:
        f.write(digest)

def sha256_hex_of_file(fp) -> str:
    h = hashlib.sha256()
    for chunk in iter(lambda: fp.read(1024 * 1024), b""):
        h.update(chunk)
    return h.hexdigest()

def sha256_hex_of_bytes(b: bytes) -> str:
    h = hashlib.sha256()
    h.update(b)
    return h.hexdigest()

# ---------- Docker Hub session/auth ----------
def dockerhub_token(repository: str, scope: str = "pull") -> str:
    r = requests.get(
        "https://auth.docker.io/token",
        params={"service": "registry.docker.io", "scope": f"repository:{repository}:{scope}"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["token"]

def get_session(repository: str) -> requests.Session:
    # Keep one Session per thread for connection reuse.
    if getattr(TLS, "session", None) is None:
        s = requests.Session()
        # Best-effort token; if it fails, continue without Authorization.
        try:
            tok = dockerhub_token(repository, "pull")
            s.headers["Authorization"] = f"Bearer {tok}"
        except Exception:
            pass
        TLS.session = s
    return TLS.session

# ---------- Image ref parsing ----------
def parse_ref(line: str) -> Optional[Tuple[str, str]]:
    line = line.strip()
    if not line:
        return None
    # repo[:tag] (default tag=latest)
    if ":" in line.split("/")[-1]:
        repo, tag = line.rsplit(":", 1)
    else:
        repo, tag = line, "latest"
    # "library" fallback if single segment like "ubuntu"
    if "/" not in repo:
        repo = f"library/{repo}"
    return repo, tag

# ---------- HTTP helpers with simple retry ----------
def _with_retry(fn, *, retries=5, base_delay=1.0, max_delay=8.0):
    last = None
    for i in range(retries):
        try:
            return fn()
        except requests.HTTPError as e:
            status = e.response.status_code if e.response is not None else None
            # Retry on 429 and 5xx
            if status in (429, 500, 502, 503, 504):
                delay = min(max_delay, base_delay * (2 ** i))
                time.sleep(delay)
                last = e
                continue
            raise
        except (requests.ConnectionError, requests.Timeout) as e:
            delay = min(max_delay, base_delay * (2 ** i))
            time.sleep(delay)
            last = e
            continue
    if last:
        raise last

# ---------- Manifest & blob fetch ----------
def fetch_manifest(repo: str, ref: str) -> Tuple[bytes, dict, str]:
    """
    Return (manifest_bytes, manifest_json, content_type).
    If ref resolves to a list/index, select linux/amd64 manifest.
    """
    s = get_session(repo)

    def _get(url):
        r = s.get(url, headers={"Accept": ACCEPT}, timeout=60)
        r.raise_for_status()
        return r

    r = _with_retry(lambda: _get(f"{SRC_REG}/v2/{repo}/manifests/{ref}"))
    ct = r.headers.get("Content-Type", "")
    body = r.content

    if "manifest.list.v2+json" in ct or "image.index.v1+json" in ct:
        idx = r.json()
        picked = None
        for m in idx.get("manifests", []):
            p = m.get("platform", {})
            if p.get("os") == "linux" and p.get("architecture") == "amd64":
                picked = m["digest"]
                break
        if not picked:
            raise RuntimeError(f"linux/amd64 not found in index for {repo}:{ref}")

        r2 = _with_retry(lambda: _get(f"{SRC_REG}/v2/{repo}/manifests/{picked}"))
        ct = r2.headers.get("Content-Type", "")
        body = r2.content

    man = json.loads(body.decode("utf-8"))
    return body, man, ct

def stream_download_blob(repo: str, digest: str, dest_path: str):
    """
    Stream download a blob from Docker Hub into dest_path.
    Verify sha256 while writing.
    Skip if file already exists or was downloaded by another thread.
    """
    # Check if already present on disk
    if os.path.exists(dest_path):
        with DOWNLOADED_LOCK:
            DOWNLOADED.add(digest)
        return

    # Best-effort in-memory dedup
    with DOWNLOADED_LOCK:
        if digest in DOWNLOADED:
            return
        # Tentatively mark as in-progress to reduce duplicate downloads
        DOWNLOADED.add(digest)

    s = get_session(repo)
    url = f"{SRC_REG}/v2/{repo}/blobs/{digest}"

    def _get_stream():
        r = s.get(url, stream=True, timeout=600)
        r.raise_for_status()
        return r

    with _with_retry(_get_stream) as r:
        algo, hexd = digest.split(":", 1)
        h = hashlib.sha256()
        ensure(os.path.dirname(dest_path))
        tmp = dest_path + ".part"
        with open(tmp, "wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    h.update(chunk)
                    f.write(chunk)
        got = h.hexdigest()
        if got != hexd:
            # Clear downloaded marker on mismatch so another attempt can proceed
            with DOWNLOADED_LOCK:
                DOWNLOADED.discard(digest)
            os.remove(tmp)
            raise RuntimeError(f"SHA256 mismatch for {digest}: got {got}")
        os.replace(tmp, dest_path)

# ---------- Registry mapping (repositories/* links) ----------
def map_repository(root: str, repo: str, tag: str, manifest_digest: str, config: str, layers: List[str]):
    regv2 = os.path.join(root, "docker", "registry", "v2")
    repo_root = os.path.join(regv2, "repositories", *repo.split("/"))

    # _layers (config + layers)
    for dg in [config] + list(layers):
        hexd = dg.split(":", 1)[1]
        link = os.path.join(repo_root, "_layers", "sha256", hexd, "link")
        write_link(link, dg)

    # revisions/<mdgst>/link
    mdhex = manifest_digest.split(":", 1)[1]
    rev_link = os.path.join(repo_root, "_manifests", "revisions", "sha256", mdhex, "link")
    write_link(rev_link, manifest_digest)

    # tags/<tag>/index/sha256/<mdgst>/link
    idx_link = os.path.join(repo_root, "_manifests", "tags", tag, "index", "sha256", mdhex, "link")
    write_link(idx_link, manifest_digest)

    # tags/<tag>/current/link
    cur_link = os.path.join(repo_root, "_manifests", "tags", tag, "current", "link")
    write_link(cur_link, manifest_digest)

# ---------- Per-image worker ----------
def process_image(out: str, repo: str, tag: str) -> Dict[str, str]:
    """
    Process one image (repo:tag):
    - fetch manifest (or selected manifest from index)
    - compute manifest digest and store as a blob (if missing)
    - download config + layers if missing
    - write repository links
    Returns a small index dict for debugging.
    """
    # Fetch manifest (or selected platform manifest)
    man_bytes, man, mct = fetch_manifest(repo, tag)
    mdhex = sha256_hex_of_bytes(man_bytes)
    mdgst = f"sha256:{mdhex}"

    # Prepare list of required blobs for this image
    cfg = man["config"]["digest"]
    layers = [l["digest"] for l in man.get("layers", [])]

    # Ensure manifest blob exists (write bytes directly if missing)
    m_dest = blob_file_path(out, mdgst)
    if not os.path.exists(m_dest):
        ensure(os.path.dirname(m_dest))
        tmp = m_dest + ".part"
        with open(tmp, "wb") as f:
            f.write(man_bytes)
        # Verify content hash just in case
        with open(tmp, "rb") as f:
            got = sha256_hex_of_file(f)
        if got != mdhex:
            os.remove(tmp)
            raise RuntimeError(f"Manifest blob sha mismatch for {mdgst}")
        os.replace(tmp, m_dest)
        with DOWNLOADED_LOCK:
            DOWNLOADED.add(mdgst)

    # Download config + layer blobs (skip existing)
    for dg in [cfg] + layers:
        dest = blob_file_path(out, dg)
        if os.path.exists(dest):
            with DOWNLOADED_LOCK:
                DOWNLOADED.add(dg)
            continue
        # Find any repo that can serve this blob; we use the current repo for simplicity.
        stream_download_blob(repo, dg, dest)

    # Write repository links so the registry can discover the tag
    map_repository(out, repo, tag, mdgst, cfg, layers)

    # Return meta for a global index
    return {
        "repo": repo,
        "tag": tag,
        "manifest_digest": mdgst,
        "config": cfg,
        "layers": layers,
        "manifest_media_type": mct,
    }

# ---------- Main ----------
def main():
    ap = argparse.ArgumentParser(description="Seed a registry:2.8.3 data dir from Docker Hub images (parallel, image-by-image).")
    ap.add_argument("--images", required=True, help="Text file: one <repo[:tag]> per line")
    ap.add_argument("--out", required=True, help="Output dir (mount this as /var/lib/registry)")
    ap.add_argument("--workers", type=int, default=min(8, (os.cpu_count() or 4)*2),
                    help="Number of parallel image workers (default: 2x CPUs, capped at 8)")
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    regv2 = os.path.join(out, "docker", "registry", "v2")
    ensure(os.path.join(regv2, "blobs"))
    ensure(os.path.join(regv2, "repositories"))

    # Parse image list
    with open(args.images, "r", encoding="utf-8") as f:
        raw_lines = [ln.strip() for ln in f if ln.strip()]
    refs = [parse_ref(ln) for ln in raw_lines]
    refs = [r for r in refs if r is not None]

    results = []
    errors = []

    # Process images in parallel (image-by-image)
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        fut2ref = {ex.submit(process_image, out, repo, tag): (repo, tag) for (repo, tag) in refs}
        for fut in as_completed(fut2ref):
            repo, tag = fut2ref[fut]
            try:
                res = fut.result()
                results.append(res)
                print(f"[ok] {repo}:{tag}")
            except Exception as e:
                errors.append((repo, tag, str(e)))
                print(f"[err] {repo}:{tag} -> {e}")

    # Write a combined index for reference/debugging (not used by registry)
    meta_dir = os.path.join(out, "meta")
    ensure(meta_dir)
    with open(os.path.join(meta_dir, "index.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print(f"[done] images={len(refs)}, ok={len(results)}, err={len(errors)}")
    if errors:
        print("[errors]")
        for repo, tag, msg in errors:
            print(f" - {repo}:{tag} -> {msg}")
    print(f"[next] start registry with:")
    print(f"docker run -d --name registry -p 5000:5000 -v {out}:/var/lib/registry registry:2.8.3")

if __name__ == "__main__":
    main()
