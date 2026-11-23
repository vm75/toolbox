# Linux/AMD64 host builder for Entware armv7sf-k3.2 *static musl* btop.
# Soft-float ABI: armv7-unknown-linux-musleabi (not musleabihf).
FROM ubuntu:24.04
LABEL org.opencontainers.image.source="https://github.com/vm75/toolbox"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils git make file binutils \
    && rm -rf /var/lib/apt/lists/*
COPY images/install-musl-toolchain.sh /tmp/install-musl-toolchain.sh
RUN bash /tmp/install-musl-toolchain.sh armv7-unknown-linux-musleabi \
    2ff70f31b1e3b3708b1a7c48d846a5781917d85b49b90a3b75344e7bed2656e5 \
    && rm /tmp/install-musl-toolchain.sh

RUN groupadd -g 1001 builder && useradd -m -s /bin/bash -u 1001 -g 1001 builder
USER builder
WORKDIR /workspace
