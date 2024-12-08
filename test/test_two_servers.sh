#!/bin/bash

# Build test images
docker build -t dslice-test:base -f Dockerfile.base ./
docker build -t dslice-test:new -f Dockerfile.new ./

# Run online server
docker run -it -d -p5001:5000 -v$(pwd)/registry_online:/var/lib/registry --name docker-registry-online registry:2.8.3

# Push base to the online, backup base to offline, and save new via online
export DSLICE_PORT=5001 DSLICE_CONTAINER_NAME=docker-registry-online
../dslice push dslice-test:base
ls registry_online/docker/registry/v2/blobs/sha256/* # 3 files
sudo cp -r registry_online registry_offline # back up base
../dslice save dslice-test:new
ls registry_online/docker/registry/v2/blobs/sha256/* # 6 files

# Run offline server
docker run -it -d -p5002:5000 -v$(pwd)/registry_offline:/var/lib/registry --name docker-registry-offline registry:2.8.3

# Pull new via offline server
export DSLICE_PORT=5002 DSLICE_CONTAINER_NAME=docker-registry-offline
ls registry_offline/docker/registry/v2/blobs/sha256/* # 3 files
../dslice load dslice-test-new.tar.gz
ls registry_offline/docker/registry/v2/blobs/sha256/* # 6 files

# Dispose resources
sudo rm -rf registry_online registry_offline dslice-test-new.tar.gz
docker stop docker-registry-online docker-registry-offline
docker rm docker-registry-online docker-registry-offline
docker rmi dslice-test:base dslice-test:new