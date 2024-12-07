#!/bin/bash

# defauilt port
DSLICE_PORT=${DSLICE_PORT:-5000}
DSLICE_URL=localhost:$DSLICE_PORT
DSLICE_CONTAINER_NAME=${DSLICE_CONTAINER_NAME:-dslice-registry}


echod() {
  echo "[DSlice]" "$@"
}

set_registry_home() {
  DSLICE_REGISTRY_HOME=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{println .Source}}{{end}}{{end}}' $DSLICE_CONTAINER_NAME)
  DSLICE_REGISTRY_DATA_LOCATION=$DSLICE_REGISTRY_HOME/docker/registry/v2
  DOCKER_REGISTRY_DATA_LOCATION=/var/lib/registry/docker/registry/v2
}

print_registry_tag() {
  TAG=$1
  TAG=${TAG//\//-} # we are in a single repository
  if [[ "$TAG" != *:* ]]; then
    TAG="${TAG}:latest"
  fi
  echo $TAG
}

# push [TAG1] [TAG2]... [TAGN]: push one or more images into registry
push_images() {
  echod "Pushing to the registry..."
  for $HOST_TAG in "$@"; do
    REGISTRY_TAG=$DSLICE_URL/$(print_registry_tag HOST_TAG)
    docker tag $HOST_TAG $REGISTRY_TAG > /dev/null
    docker push $REGISTRY_TAG
    docker rmi $REGISTRY_TAG > /dev/null
  done
  echod "Done."
}

# pull [TAG1] [TAG2]... [TAGN]: pull one or more images from registry
pull_images() {
  echod "Pulling from the registry..."
  for HOST_TAG in "$@"; do
    REGISTRY_TAG=$DSLICE_URL/$(print_registry_tag HOST_TAG)
    docker pull $REGISTRY_TAG 
    docker tag $REGISTRY_TAG $HOST_TAG > /dev/null
    docker rmi $REGISTRY_TAG > /dev/null
  done
  echod "Done."
}

delete_image() {
  # Split tag into base name and version
  REGISTRY_TAG=$(print_registry_tag $1)
  TAG_BASE=${REGISTRY_TAG%%:*}
  VERSION=${REGISTRY_TAG##*:}

  echod "Deleting the image from the registry..."
  # Send DELETE request to registry
  # Thanks to https://gist.github.com/jaytaylor/86d5efaddda926a25fa68c263830dac1
  curl -v -X DELETE "http://$DSLICE_URL/v2/${TAG_BASE}/manifests/$(
    curl -I -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "http://$DSLICE_URL/v2/${TAG_BASE}/manifests/$VERSION" \
    | awk '$1 == "Docker-Content-Digest:" { print $2 }' \
    | tr -d $'\r' \
    )"
  # Run the garbage collector
  docker exec -it $DSLICE_CONTAINER_NAME /bin/registry garbage-collect /etc/docker/registry/config.yml
  #! To flush the previous image, we need to restart the container (https://github.com/distribution/distribution/issues/2270)
  docker restart $DSLICE_CONTAINER_NAME

  echod "Done"
}

# save [TAG]: 
#     1. push the image into registry and exclude mounted blobs from target blobs
#     2. copy target blobs and image manifest
#     3. archive the partial image
save_image() { 
  HOST_TAG=$1
  REGISTRY_TAG=$(print_registry_tag $HOST_TAG)
  TAG_BASE=${REGISTRY_TAG%%:*}
  VERSION=${REGISTRY_TAG##*:}
  REGISTRY_TAG=$DSLICE_URL/$REGISTRY_TAG

  set_registry_home

  # Collect target blobs with pushing
  echod "Pushing to the registry..."
  docker tag $HOST_TAG $REGISTRY_TAG > /dev/null
  TIMESTAMP_BEFORE_PUSH=$(date +%s)
  docker push $REGISTRY_TAG > /dev/null
  TARGET_BLOBS="$(find $DSLICE_REGISTRY_DATA_LOCATION/blobs/sha256 -type f -newermt "@$TIMESTAMP_BEFORE_PUSH")"
  # TARGET_BLOBS=$(docker push $REGISTRY_TAG | tee /dev/tty | grep ": Pushed" | awk -F ':' '{print $1}') # image hash is not the blob hash

  echod "Following blobs are exclusive from base images"
  echo $TARGET_BLOBS

  echod "Copying the files..."
  cd $DSLICE_REGISTRY_HOME
  OUTPUT_DIR=".dslice-image"
  rm -rf $OUTPUT_DIR && mkdir -p $OUTPUT_DIR/blobs $OUTPUT_DIR/manifest

  # Copy the target manifest and blobs
  cp -r $DSLICE_REGISTRY_DATA_LOCATION/repositories/$TAG_BASE $OUTPUT_DIR/manifest
  for BLOB_DATA_DIR in $TARGET_BLOBS; do
    BLOB_DIR=${BLOB_DATA_DIR%%/data}
    cp -r $BLOB_DIR $OUTPUT_DIR/blobs
  done
  echo $VERSION > VERSION

  echod "Archiving..."
  tar -cf ${TAG_BASE}-${VERSION}.tar.gz $OUTPUT_DIR

  rm -rf $OUTPUT_DIR

  docker rmi $REGISTRY_TAG > /dev/null
  echod "Done. The output image archive is located in $DSLICE_REGISTRY_HOME/${TAG_BASE}-${VERSION}.tar.gz"
}

# build [docker build args]: 
#     1. build an image from Dockerfile (docker build)
#     2. save image as a tarball (save)
build_image() {
  DOCKER_BUILD_ARGS=$@
  HOST_TAG=$(echo $DOCKER_BUILD_ARGS | grep -oP "(?<=-t )\S+")

  echod "Building image with tag: $HOST_TAG"
  docker build $DOCKER_BUILD_ARGS
  save_image $HOST_TAG
}

# load [image tarball]: 
#     1. extract the image to the registry (blobs, manifest)
#     2. restart the container and pull the image the local
load_image() {
  IMAGE_TARBALL=$1
  
  set_registry_home

  echod "Loading image from $IMAGE_TARBALL..."
  OUTPUT_DIR=".dslice-image"
  rm -rf $OUTPUT_DIR
  cd $DSLICE_REGISTRY_HOME && tar -xvf $IMAGE_TARBALL 

  IMAGE_NAME=$(ls $OUTPUT_DIR/manifest)
  IMAGE_VERSION=$(cat $OUTPUT_DIR/VERSION)
  
  docker cp $OUTPUT_DIR/manifest/$IMAGE_NAME $DSLICE_CONTAINER_NAME:$DOCKER_REGISTRY_DATA_LOCATION/repositories 
  
  BLOBS=$(ls $OUTPUT_DIR/blobs)
  for BLOB in $BLOBS; do
    BLOB_LOOKUP_KEY=${BLOB:0:2}
    TARGET_DIR=$DOCKER_REGISTRY_DATA_LOCATION/blobs/sha256/$BLOB_LOOKUP_KEY
    docker exec -it $DSLICE_CONTAINER_NAME mkdir -p $TARGET_DIR
    docker cp $OUTPUT_DIR/blobs/$BLOB $DSLICE_CONTAINER_NAME:$TARGET_DIR
  done
  rm -rf $OUTPUT_DIR

  echod "Restarting the registry server for synchronization..."
  docker restart $DSLICE_CONTAINER_NAME

  echod "Pulling image from the registry..."
  HOST_TAG=$IMAGE_NAME:$IMAGE_VERSION
  REGISTRY_TAG=$DSLICE_URL/$HOST_TAG
  docker pull $REGISTRY_TAG
  docker tag $REGISTRY_TAG $HOST_TAG
  docker rmi $REGISTRY_TAG
  echod "Done. the image $HOST_TAG was pulled on the host."
}

case $1 in
  push)
    shift
    push_images "$@"
    ;;
  pull)
    shift
    pull_images "$@"
    ;;
  delete)
    shift
    delete_image "$@"
    ;;
  build)
    shift
    build_image "$@"
    ;;
  save)
    shift
    save_image "$@"
    ;;
  load)
    shift
    load_image "$1"
    ;;
  *)
    echo "Usage: $0 {push|pull|build|save|load}"
    exit 1
    ;;
esac
