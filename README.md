# DockerSlice: Ship Only The Latest Layers You Update

An efficient Docker image transfer system that extracts and merges necessary image layers. (designed for offline docker users)

# How to Use?

**Step 1:** Clone and run the DockerSlice system (`dslice base run`) on both your online and offline servers. This will set up the DockerSlice registry.

**Step 2**: You can use DockerSlice in two ways:

1. **Share a Common Base Image:**

- Push the [base images](#docker-base-images) to both servers.
- Build custom images on top of the shared base images.
- Transfer only the new layers above the base, minimizing data transfer.

2. **Partial Updates:**

- When a Docker image on the offline server needs an update, make an update on the image online (e.g., install a package).
- Then, move only the updated layers to the offline server.

<img width="688" alt="image" src="https://github.com/user-attachments/assets/6f367d37-709b-4f7b-8109-6cba191a3e42" />

# Docker base images
For easier sharing of base images, DockerSlice provides several pre-configured base images:

- `dslice-base`: A CUDA base image with essential tools (e.g., Git, Vim, OpenSSH).
- `dslice-base-py`: A Conda-based image with a specific Python version, built on `dslice-base`.
- `dslice-base-torch`: A PyTorch image with a specific Python version, built on `dslice-base-py`.


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
