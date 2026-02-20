# DockerDiff: Diff Only The Latest Layers You Update

An efficient Docker image transfer system that extracts the diff of two images and loads only the diff into the server. (designed for offline docker users)


<img width="688" alt="image" src="https://github.com/user-attachments/assets/6f367d37-709b-4f7b-8109-6cba191a3e42" />


# Getting Started

### Install DockerDiff
```
git clone https://github.com/junwha/DockerDiff
cd DockerDiff
./install.sh
source ~/.bashrc
```

### Basic Usage: Build on the base image, and load the diff

1. Push the [base image](#docker-base-images) into the offline registry server

    i. Run the registry server `ddiff server` (optional, you can use your own server by setting the env variable DDIFF_URL)

    ii. `ddiff push <base tag>`

2. Run the ddiff server, and build a new image on top of the base image.
    
   i. Write a Dockerfile with `FROM <base tag>`

   ii. Run the registry server `ddiff server`. This will generate the diff file `<new>-<version>.tar.gz`
   
      `ddiff build -t <new tag>:<version> ./` 

3. Transfer only the diff file (`<new tag>-<version>.tar.gz`) to the offline server

4. Load the diff file at the offline server

     `ddiff load <new tag>-<version>.tar.gz`

### Diff the existing two images

1. Make a diff file (`<new tag>-<version>.tar.gz`) of the target image from the base image

    `ddiff diff <base tag> <target tag>`

2. Transfer the diff file and load at the offline server

    `ddiff load <new tag>-<version>.tar.gz`

### Patch the image in the offline

1. Modify the existing Dockerfile or make a new Dockerfile on top of the image in the offline (FROM <offline tag>:<prev version>)

2. Build the Dockerfile with ddiff

     `ddiff build -t <offline tag>:<new version> ./` 

3. Transfer the diff file and load at the offline server

    `ddiff load  <offline tag>-<new version>.tar.gz`

# Commands

**Usage**: `ddiff <command> <args...>`

**Commands**
  - `server`                      - Run the registry server
  - `push` `<tag 1> ... <tag n>`   - Push one or more images
  - `pull` `<tag 1> ... <tag n>`    - Pull one or more images
  - `diff` `<base> <target>`       - Diff the target image from the base image
  - `load` `<tar file>`             - Load the target image from diff file
  - `build` `<args>`                - Build the image and diff from base (FROM ...)

# Docker base images
For easier sharing of base images, DockerDiff provides several pre-configured base images. 

```
docker pull junwha/ddiff-base:cu12.4.1-py3.10-torch-251214
```

For more details, visit [dockerfiles](dockerfiles)

# Requirements
- Python 3.X
- (optional, if you use podman) skopeo

# Registry/API compatibility
- Docker Registry HTTP API V2 endpoints are used (`/v2/<name>/manifests/<reference>`, `/v2/<name>/blobs/<digest>`).
- Both Docker image manifest V2 and OCI image types are supported.
