FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/vm75/toolbox"

ENV DEBIAN_FRONTEND=noninteractive

# Install host compilation packages required by the Entware buildroot
RUN for attempt in 1 2 3; do \
        apt-get update -o Acquire::Retries=3 && break || { \
            if [ "$attempt" -eq 3 ]; then exit 1; fi; \
            echo "apt-get update failed (attempt $attempt/3); retrying in 5s..."; \
            sleep 5; \
        }; \
    done && \
    apt-get install -y --no-install-recommends -o Acquire::Retries=3 \
        build-essential git curl wget ca-certificates gnupg python3 python3-setuptools \
        perl rsync subversion unzip zip file gawk gettext flex bison cpio bc \
        libncurses-dev libssl-dev zlib1g-dev libelf-dev libxslt1-dev \
        pkg-config time patch diffutils util-linux xz-utils zstd cmake ninja-build swig \
        autoconf automake libtool libtool-bin texinfo sudo \
        && rm -rf /var/lib/apt/lists/*

# Entware buildroot forbids building as root.
# Create a builder user with UID 1001 (matching GitHub Actions runner).
RUN groupadd -g 1001 builder 2>/dev/null || true && \
    useradd -m -s /bin/bash -u 1001 -g 1001 builder 2>/dev/null || useradd -m -s /bin/bash -u 1001 builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

# Configure git safe directory globally
RUN git config --system --add safe.directory '*'

# Prepare toolchain directory owned by builder
RUN mkdir -p /opt/nginx-entware && chown -R builder:builder /opt/nginx-entware

USER builder
WORKDIR /opt/nginx-entware

# Copy build script into container to pre-build the cross-toolchain
COPY --chown=builder:builder tools/nginx/upstream-builder.sh /tmp/build-toolchain.sh

ARG JOBS=4
RUN bash /tmp/build-toolchain.sh --target aarch64-3.10 --toolchain-only --jobs "${JOBS}" --workdir /opt/nginx-entware \
    && rm -f /tmp/build-toolchain.sh

# GCC 8.4 is needed by Entware/nginx but cannot compile modern btop (C++23).
# Provide the separately pinned GCC 15.2 musl compiler for static btop.
USER root
COPY images/install-musl-toolchain.sh /tmp/install-musl-toolchain.sh
RUN bash /tmp/install-musl-toolchain.sh aarch64-unknown-linux-musl \
    28a1d26f14f8ddc3aed31f20705fe696777400eb5952d90470a7e6e2dd1175bb \
    && rm /tmp/install-musl-toolchain.sh
# Fail image publishing early if the C++23 compiler or static target ABI is wrong.
RUN printf '#include <iostream>\nint main(){std::cout << "ok";}\n' | \
    /opt/x-tools/aarch64-unknown-linux-musl/bin/aarch64-unknown-linux-musl-g++ \
      -std=c++23 -static -x c++ - -o /tmp/entware-smoke \
    && readelf -h /tmp/entware-smoke | grep -Eq 'Machine:.*AArch64([[:space:]]|$)' \
    && ! readelf -l /tmp/entware-smoke | grep -q 'Requesting program interpreter' \
    && rm /tmp/entware-smoke

USER builder
WORKDIR /workspace
