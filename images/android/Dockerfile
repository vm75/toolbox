# Android builder for Librera/MuPDF and Cryptomator.
# Only SDKs and compilers live in the image; source and APK signing secrets never do.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/vm75/toolbox"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip zip git git-lfs \
    openjdk-21-jdk-headless \
    build-essential pkg-config cmake ninja-build python3 python3-pip \
    perl rsync file libssl-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.2.12479018 \
    LIBRERA_NDK_DIR=/opt/android-sdk/ndk/27.2.12479018
ENV PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

# Pin the official Google command-line tools archive to avoid unplanned image changes.
ARG CMDLINE_TOOLS_REV=15859902
ARG CMDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && curl -fL --retry 3 \
      "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_REV}_latest.zip" \
      -o /tmp/android-tools.zip \
    && echo "${CMDLINE_TOOLS_SHA256}  /tmp/android-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/android-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest" \
    && rm /tmp/android-tools.zip

# SDK API 37 and build-tools 37.0.0 are used by both upstream Android projects.
# MuPDF's JPEG XL build requires NDK r27d and CMake.
RUN yes | sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" --licenses > /dev/null \
    && sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" \
      "platform-tools" "platforms;android-37" "build-tools;37.0.0" \
      "ndk;27.2.12479018" "cmake;3.22.1" \
    && test -x "${ANDROID_NDK_HOME}/ndk-build"

# Match the UID on GitHub-hosted Ubuntu runners for bind-mounted workspaces.
RUN groupadd -g 1001 builder \
    && useradd -m -s /bin/bash -u 1001 -g 1001 builder \
    && chown -R builder:builder "${ANDROID_SDK_ROOT}"
USER builder
WORKDIR /workspace
