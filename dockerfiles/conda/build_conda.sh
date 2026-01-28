PY_VERSION=$1
DATE=251214 # $(date +"%y%m%d")
TAG=junwha/ddiff-base:cu12.4.1-py${PY_VERSION}-conda-$DATE

docker build -t $TAG --build-arg PY_VERSION=${PY_VERSION} ./ 

# && \
# ./test.sh $TAG && docker push $TAG