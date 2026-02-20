import sys
import os
import subprocess
import shutil
import tarfile
import time
from pathlib import Path
import urllib
import urllib.request
import urllib.parse
import json
import re

DOCKER_MANIFEST_V2 = "application/vnd.docker.distribution.manifest.v2+json"
DOCKER_MANIFEST_LIST_V2 = "application/vnd.docker.distribution.manifest.list.v2+json"
OCI_MANIFEST_V1 = "application/vnd.oci.image.manifest.v1+json"
OCI_INDEX_V1 = "application/vnd.oci.image.index.v1+json"

SUPPORTED_MANIFEST_TYPES = [
    DOCKER_MANIFEST_V2,
    OCI_MANIFEST_V1,
]

ACCEPT_MANIFEST_TYPES = ", ".join([
    *SUPPORTED_MANIFEST_TYPES,
    DOCKER_MANIFEST_LIST_V2,
    OCI_INDEX_V1,
])

# Default values
ddiff_port = os.getenv("DDIFF_PORT", "5000")
ddiff_url = os.getenv("DDIFF_URL")
ddiff_url = f"http://localhost:{ddiff_port}" if ddiff_url is None else ddiff_url
ddiff_url_base = ddiff_url.replace("https://", "").replace("http://", "").replace("//", "/")
ddiff_container_name = os.getenv("DDIFF_CONTAINER_NAME", "ddiff-registry")
ddiff_register_volume = os.getenv("DDIFF_REGISTRY_VOLUME")
ddiff_disable_repository = os.getenv("DDIFF_DISABLE_RESPOSITORY", False)

def print_debug(*args):
    print("[ddiff]", *args)

def print_error(*args):
    print("[Error]", *args)
    raise RuntimeError

def run_command(cmd, capture_output=False):
    result = subprocess.run(cmd, shell=True, text=True, capture_output=capture_output)
    return result.stdout.strip() if capture_output else None

# def get_registry_info():
#     cmd = f"docker inspect --format '{{{{range .Mounts}}}}{{{{if eq .Type \"bind\"}}}}{{{{println .Source}}}}{{{{end}}}}{{{{end}}}}' {ddiff_container_name}"
#     ddiff_registry_home = run_command(cmd, capture_output=True).splitlines()[0]
#     ddiff_registry_data_location = os.path.join(ddiff_registry_home, "docker/registry/v2")
#     docker_registry_data_location = "/var/lib/registry/docker/registry/v2"
    
#     return ddiff_registry_home, ddiff_registry_data_location, docker_registry_data_location

def _prepare_tag(tag):
    if ddiff_disable_repository:
        tag = tag.replace("/", "-")
    if ":" not in tag:
        tag += ":latest"
    return tag

def _request_manifest(tag):
    repo, version_tag = tag.split(":")
    manifest_url = f"{ddiff_url}/v2/{repo}/manifests/{version_tag}"

    req = urllib.request.Request(manifest_url)
    req.add_header("Accept", ACCEPT_MANIFEST_TYPES)
    try:
        with urllib.request.urlopen(req) as response:
            manifest = response.read().decode()
            content_type = (response.getheader("Content-Type") or "").split(";")[0]
            return manifest, content_type
    except urllib.error.HTTPError as e:
        print_error(f"HTTP error: {e.code} - {e.reason} ({manifest_url})")
    except Exception as e:
        print_error(f"Error: {e} ({manifest_url})")
    
def _validate_manifest_media_type(manifest):
    media_type = manifest.get("mediaType", "")
    if media_type in [DOCKER_MANIFEST_LIST_V2, OCI_INDEX_V1]:
        print_error("Manifest list/index is not supported yet. Please provide a single image manifest tag.")
    if media_type and media_type not in SUPPORTED_MANIFEST_TYPES:
        print_error(f"Unsupported manifest mediaType: {media_type}")
    return media_type


def _parse_blob_list(manifest_str):
    manifest = json.loads(manifest_str)
    _validate_manifest_media_type(manifest)
    digests = []

    # Config blob
    if "config" in manifest and "digest" in manifest["config"]:
        digests.append(manifest["config"]["digest"])

    # Layer blobs
    for layer in manifest.get("layers", []):
        if "digest" in layer:
            digests.append(layer["digest"])

    return digests

def _download_blob(repo, digest, output_path):
    if not re.match(r"^[a-z0-9_+.-]+:[a-fA-F0-9]+$", digest):
        print_error(f"Invalid digest format: {digest}")

    blob_url = f"{ddiff_url}/v2/{repo}/blobs/{digest}"

    try:
        with urllib.request.urlopen(blob_url) as response, open(f"{output_path}/{digest}.tar", 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
        print_debug(f"Downloaded {digest}")
    except urllib.error.HTTPError as e:
        print_error(f"HTTP error {e.code} while downloading blob from: {blob_url}")
    except Exception as e:
        print_error(f"Unexpected error: {e} ({blob_url})")

def _request_upload_session(repo):
    url = f"{ddiff_url}/v2/{repo}/blobs/uploads/"
    req = urllib.request.Request(url, method="POST")
    try:
        with urllib.request.urlopen(req) as res:
            location = res.getheader("Location")
            return location
    except urllib.error.HTTPError as e:
        print_error(f"Failed to start upload: {e.code} {e.reason}  ({url})")

def _upload_blob(repo, digest, blob_dir):
    try:
        # Open upload session
        session_url = _request_upload_session(repo)
        # Load tar file of the layer
        with open(f"{blob_dir}/{digest}.tar", 'rb') as f:
            data = f.read()
        delimiter = "&" if "?" in session_url else "?"
        full_url = f"{session_url}{delimiter}digest={urllib.parse.quote(digest)}"
        req = urllib.request.Request(full_url, data=data, method="PUT")
        req.add_header("Content-Type", "application/octet-stream")
        with urllib.request.urlopen(req) as res:
            print_debug(f"Uploaded {digest} (status {res.status})")
    except urllib.error.HTTPError as e:
        print_error(f"Upload failed for {digest}: {e.code} {e.reason} ({full_url})")

def _cross_mount(target_repo, base_repo, digest):
    url = f"{ddiff_url}/v2/{target_repo}/blobs/uploads/?mount={digest}&from={base_repo}"
    req = urllib.request.Request(url, method="POST")
    try:
        with urllib.request.urlopen(req) as res:
            if res.status == 201:
                print_debug(f"Mounted {digest} from {base_repo} to {target_repo}")
            elif res.status == 202:
                print_error(f"Mount fallback: {digest} not found in {base_repo} ({url})")
    except urllib.error.HTTPError as e:
        print_error(f"Mount failed: {e.code} {e.reason} ({url})")

def _upload_manifest(tag, manifest_path, manifest_media_type=DOCKER_MANIFEST_V2):
    repo, version_tag = tag.split(":")
    url = f"{ddiff_url}/v2/{repo}/manifests/{version_tag}"
    try:
        with open(manifest_path, 'rb') as f:
            data = f.read()
        req = urllib.request.Request(url, data=data, method="PUT")
        req.add_header("Content-Type", manifest_media_type)
        with urllib.request.urlopen(req) as res:
            print_debug(f"Manifest uploaded to {repo} (status {res.status})")
    except urllib.error.HTTPError as e:
        print_error(f"Manifest upload failed: {e.code} {e.reason} ({url})")

def run_registry():
    volume_arg = "" if ddiff_register_volume is None else f"-v{ddiff_register_volume}:/var/lib/registry"

    cmd = f"docker run -it -d -p{ddiff_port}:5000 --name {ddiff_container_name} registry:2.8.3"
    run_command(cmd)

def push_images(tags):
    print_debug("Pushing to the registry...")
    for host_tag in tags:
        registry_tag = f"{ddiff_url_base}/{_prepare_tag(host_tag)}"
        run_command(f"docker tag {host_tag} {registry_tag}")
        print("a", f"docker tag {host_tag} {registry_tag}")
        run_command(f"docker push {registry_tag}")
        print("b")
        run_command(f"docker rmi {registry_tag}")
    # print_debug("Done.")

def pull_images(tags):
    print_debug("Pulling from the registry...")
    for host_tag in tags:
        registry_tag = f"{ddiff_url_base}/{_prepare_tag(host_tag)}"
        run_command(f"docker pull {registry_tag}")
        run_command(f"docker tag {registry_tag} {host_tag}")
        run_command(f"docker rmi {registry_tag}")
    # print_debug("Done.")

def diff_image(base_tag, target_tag):
    push_images([base_tag, target_tag])

    base_tag = _prepare_tag(base_tag)
    target_tag = _prepare_tag(target_tag)
    target_repo = target_tag.split(":")[0]

    user_dir = os.getcwd()
    output_dir = os.path.join(user_dir, ".ddiff-image")
    shutil.rmtree(output_dir, ignore_errors=True)

    blob_dir = os.path.join(output_dir, "blobs")
    os.makedirs(blob_dir)

    # Download manifest
    base_manifest, _ = _request_manifest(base_tag)
    target_manifest, target_manifest_media_type = _request_manifest(target_tag)
    
    # Download different blobs
    base_blobs = _parse_blob_list(base_manifest)
    target_blobs = _parse_blob_list(target_manifest)
    diff_blobs = set(target_blobs) - set(base_blobs)

    print_debug("Following blobs are exclusive from base images:", ",".join(diff_blobs))
    for digest in diff_blobs:
        _download_blob(target_repo, digest, blob_dir)

    # Write back metadata
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
    
    print_debug("Archiving...")
    archive_name = f"{target_tag.replace('/', '--').replace(':', '-')}.tar.gz"
    with tarfile.open(archive_name, "w:gz") as tar:
        tar.add(output_dir, arcname=".ddiff-image")

    shutil.rmtree(output_dir)
    print_debug(f"Done. Load the output image archive {archive_name} in the offline (ddiff load {archive_name})")
    print_debug(f"{archive_name}")

def load_image(base_tag, image_tarball):
    input_dir = ".ddiff-image"
    shutil.rmtree(input_dir, ignore_errors=True)
    with tarfile.open(image_tarball) as tar:
        tar.extractall()

    # Parse base tag from the manifest onlyif not given
    if base_tag is None:
        with open(os.path.join(input_dir, "BASE")) as f:
            base_tag = f.read().strip()
    base_repo = base_tag.split(":")[0]

    push_images([base_tag])
    
    with open(os.path.join(input_dir, "TARGET")) as f:
        target_tag = f.read().strip()
        target_repo = target_tag.split(":")[0]
    with open(os.path.join(input_dir, "MOUNT_BLOBS")) as f:
        mount_blobs = f.read().strip().split("|")
    with open(os.path.join(input_dir, "UPLOAD_BLOBS")) as f:
        upload_blobs = f.read().strip().split("|")

    manifest_media_type = DOCKER_MANIFEST_V2
    manifest_media_type_path = os.path.join(input_dir, "MANIFEST_MEDIA_TYPE")
    if os.path.exists(manifest_media_type_path):
        with open(manifest_media_type_path) as f:
            manifest_media_type = f.read().strip() or DOCKER_MANIFEST_V2

    # Mount
    for blob in mount_blobs:
        _cross_mount(target_repo, base_repo, blob)
    # Upload
    blob_dir = f"{input_dir}/blobs"
    for blob in upload_blobs:
        _upload_blob(target_repo, blob, blob_dir)

    _upload_manifest(target_tag, f"{input_dir}/manifest.json", manifest_media_type)

    shutil.rmtree(input_dir)

    if "localhost" in ddiff_url: 
        print_debug("Pulling image from the registry...")
        registry_tag = f"{ddiff_url_base}/{target_tag}"
        run_command(f"docker pull {registry_tag}")
        run_command(f"docker tag {registry_tag} {target_tag}")
        run_command(f"docker rmi {registry_tag}")
        print_debug(f"The image {target_tag} is sucessfully pulled on the host.\nIf you will not inherit {target_tag} in future, you can delete the image.")
    else:
        print_debug(f"The image {target_tag} is sucessfully pulled on the host.")

def build_image(build_args):
    target_tag = None
    dockerfile_str = "Dockerfile"
    for i, arg in enumerate(build_args):
        if arg == "-t" and i + 1 < len(build_args):
            target_tag = build_args[i + 1]
        if arg == "-f" and i + 1 < len(build_args):
            dockerfile_str = build_args[i + 1]
    dockerfile_path = f"{build_args[-1]}/{dockerfile_str}"

    with open(dockerfile_path) as f:
        base_tag = f.read().split("\n")[0].strip().replace("FROM ", "")

    assert not target_tag is None

    print_debug(f"Building image with tag: {target_tag}\nwe will diff image blobs of {target_tag} from {base_tag}")
    run_command("docker build " + " ".join(build_args))
    print_debug(f"Diff image blobs of {target_tag} from {base_tag}")
    diff_image(base_tag, target_tag)

def list_blobs(tag):
    push_images([tag])
    
    tag = _prepare_tag(tag)
    
    # Download manifest
    manifest, _ = _request_manifest(tag)
    
    
    # Check blobs
    blobs = _parse_blob_list(manifest)
    print("=== blobs ===")
    for blob in blobs:
        print(blob.replace("sha256:", ""))

if __name__ == '__main__':
    if len(sys.argv) < 2 or not sys.argv[1] in ["server", "push", "pull", "diff", "load", "build", "list"]:
        print("Usage: ddiff [command] [args...]")
        print("Commands:")
        print("  server                      - Run the registry server (set DDIFF_REGISTRY_VOLUME)")
        print("  push <tag 1> ... <tag n>    - Push one or more images")
        print("  pull <tag 1> ... <tag n>    - Pull one or more images")
        print("  diff <base> <target>        - Diff the target image from the base image")
        print("  load <tar file>             - Load the target image from diff file")
        print("  build <args>                - Build the image and diff from base (FROM ...)")
        print("  list <tag>                  - List up blobs of the given image")
        sys.exit(1)

    command = sys.argv[1]
    args = sys.argv[2:]

    if command == "server":
        if args:
            print("Usage: DDIFF_REGISTRY_VOLUME=<path to volume> python3 ddiff.py server")
            sys.exit(1)
        run_registry()
    elif command == "push":
        if len(args) < 1:
            print("Usage: python3 ddiff.py push <tag1> [<tag2> ...]")
            sys.exit(1)
        push_images(args)
    elif command == "pull":
        if len(args) < 1:
            print("Usage: python3 ddiff.py pull <tag1> [<tag2> ...]")
            sys.exit(1)
        pull_images(args)
    elif command == "diff":
        if len(args) != 2:
            print("Usage: python3 ddiff.py diff <target_image> <base_image>")
            sys.exit(1)
        diff_image(args[0], args[1])
    elif command == "load":
        if len(args) > 2:
            print("Usage: python3 ddiff.py load <base tag> <tar_file> or python3 ddiff.py load <tar_file>")
            sys.exit(1)
        elif len(args) == 2:
            load_image(args[0], args[1])
        elif len(args) == 1:
            load_image(None, args[0])
    elif command == "build":
        if len(args) < 1:
            print("Usage: python3 ddiff.py build <docker build args>")
            sys.exit(1)
        build_image(args)
    elif command == "list":
        if len(args) != 1:
            print("Usage: python3 ddiff.py list <tag>")
            sys.exit(1)
        list_blobs(args[0])
