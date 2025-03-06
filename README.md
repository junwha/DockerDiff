# DockerSlice: Ship Only The Latest Layers You Update

An efficient Docker image transfer system that extracts and merges necessary image layers. (designed for offline docker users)

# How to Use?

**Step 1:** Clone and run the DockerSlice system (`dslice base run`) on both your online and offline servers. This will set up the DockerSlice registry.

**Step 2**: You can use DockerSlice in two ways:

A. **Share a Common Base Image:**

1. Push the [base images](#docker-base-images) to both servers.

    `dslice push junwha/dslice-base-torch:py3.10-torch2.4.1`

3. Build custom images on top of the shared base images.
   
    Start with `FROM junwha/dslice-base-torch:py3.10-torch2.4.1` at the top of the Dockerfile
   
    `docker build -t <TAG> ./`
   
4. Save the above layers as a tar.gz file
   
    `dslice save <TAG>` (`<TAG>.tar.gz` will be created)

5. Transfer only the new layers (`<TAG>.tar.gz`) above the base, minimizing data transfer.
6. Load the tar.gz file at the offline server

     `dslice load <TAG>.tar.gz`

B. **Partial Updates:**

- When a Docker image on the offline server needs an update, make an update on the image online (e.g., install a package).
- Then, move only the updated layers to the offline server.

<img width="688" alt="image" src="https://github.com/user-attachments/assets/6f367d37-709b-4f7b-8109-6cba191a3e42" />

# Commands (will be updated)
./dslice {base|push|pull|delete|save|build|load}
- base {save|load}
    - run ([volume folder]): run dslice registry (online server)
    - save [base tarball path]: save dslice registry with base images as a tarball
    - load [base tarball] ([install directory]): load dslice registry from the tarball 
    - pull [TAG1] [TAG2] ... [TAGN]: pull one or more images as base images
- push [TAG1] [TAG2] ... [TAGN]: push one or more images into the registry
- pull [TAG1] [TAG2] ... [TAGN]: pull one or more images from the registry
- delete [TAG1]: delete the specified image from the registry
- save [TAG]: 
    1. push the image into registry and exclude mounted blobs from target blobs
    2. copy target blobs and image manifest
    3. archive the partial image
- build [docker build args]: 
    1. build an image from Dockerfile (docker build)
    2. save image as a tarball (save)
- load [image tarball]: 
    1. extract the image to the registry (blobs, manifest)
    2. restart the container and pull the image the local

# Docker base images
For easier sharing of base images, DockerSlice provides several pre-configured base images:

- [dslice-base](https://hub.docker.com/r/junwha/dslice-base): A CUDA base image with essential tools (e.g., Git, Vim, OpenSSH).
- [dslice-base-py](https://hub.docker.com/r/junwha/dslice-base-py): A Conda-based image with a specific Python version, built on `dslice-base`.
- [dslice-base-torch](https://hub.docker.com/r/junwha/dslice-base-torch): A PyTorch image with a specific Python version, built on `dslice-base-py`.
