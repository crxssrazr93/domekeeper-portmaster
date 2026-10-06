# Build environment for the sample encoder: Ubuntu 20.04 with native and aarch64 compilers.
# Both binaries are linked statically, so they run on every PortMaster CFW regardless of glibc.
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
