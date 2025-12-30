PY_VERSION=$1
TAG=junwha/ddiff-base-common:cu12.4.1-py${PY_VERSION}

docker build -t $TAG --build-arg PY_VERSION=${PY_VERSION} ./ && \
./test.sh $TAG && docker push $TAG