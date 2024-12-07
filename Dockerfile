FROM registry:2.8.3

ENV REGISTRY_STORAGE_DELETE_ENABLED true

COPY dslice.sh /

ENTRYPOINT ["sh", "-c", "cp /dslice.sh /var/lib/registry/dslice; registry serve /etc/docker/registry/config.yml"]