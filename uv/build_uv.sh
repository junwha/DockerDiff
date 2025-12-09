PY_VERSION=$1
TAG=junwha/ddiff-base:cu12.4.1-py${PY_VERSION}-torch-$(date +"%y%m%d")

docker build -t $TAG --build-arg PY_VERSION=${PY_VERSION} ./
docker push $TAG