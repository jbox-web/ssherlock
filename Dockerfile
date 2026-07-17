###########
# CRYSTAL #
###########

FROM alpine:3.24 AS crystal

RUN apk add --update --no-cache \
  bash \
  make \
  crystal=~1.20 \
  shards \
  git \
  gc-dev \
  gc-static \
  libssh2-dev \
  libssh2-static \
  openssl-dev \
  openssl-libs-static \
  pcre2-dev \
  pcre2-static \
  yaml-dev \
  yaml-static \
  zlib-dev \
  zlib-static

FROM crystal AS build-binary-file

ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ENV \
  TARGETPLATFORM=${TARGETPLATFORM} \
  TARGETOS=${TARGETOS} \
  TARGETARCH=${TARGETARCH} \
  TARGETVARIANT=${TARGETVARIANT}

WORKDIR /build
COPY .git/ /build/.git/
COPY shard.yml shard.lock /build/
COPY LICENSE licenses.manifest /build/
COPY licenses-spdx/ /build/licenses-spdx/
COPY scripts/ /build/scripts/
COPY Makefile.release /build/Makefile
COPY config/ /build/config/
COPY skills/ /build/skills/
COPY src/ /build/src/
RUN mkdir /build/bin

RUN make release

FROM scratch AS binary-file
ARG TARGETOS
ARG TARGETARCH
COPY --from=build-binary-file /build/bin/ssherlock-${TARGETOS}-${TARGETARCH} /
