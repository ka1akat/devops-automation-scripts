FROM postgres:17

ARG CITUS_VERSION=v13.2.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-server-dev-17 gcc make git ca-certificates \
      autoconf flex libcurl4-gnutls-dev libicu-dev libkrb5-dev \
      liblz4-dev libpam0g-dev libreadline-dev libselinux1-dev \
      libssl-dev libxslt1-dev libzstd-dev uuid-dev \
 && git clone --depth 1 --branch ${CITUS_VERSION} https://github.com/citusdata/citus.git /tmp/citus \
 && cd /tmp/citus \
 && ./configure \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /tmp/citus /var/lib/apt/lists/*

CMD ["postgres", "-c", "shared_preload_libraries=citus"]
