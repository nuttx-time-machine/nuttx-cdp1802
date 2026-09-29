# toolchain/Dockerfile — the same toolchain build as build-toolchain.sh,
# in a clean Ubuntu 24.04 container.
#
# Build (from the repository root):
#   docker build -f toolchain/Dockerfile -t nuttx-cdp1802-toolchain .
#
# The toolchain is installed in /opt/cdp1802, and its bin directories are
# on PATH.

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git ca-certificates bison flex texinfo \
      libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev \
      libncurses-dev libssl-dev autoconf m4 perl python3 \
      kconfig-frontends-nox xxd bc file \
    && rm -rf /var/lib/apt/lists/*

COPY toolchain/VERSIONS toolchain/build-toolchain.sh /src/toolchain/
RUN PREFIX=/opt/cdp1802 WORKDIR=/tmp/tc /src/toolchain/build-toolchain.sh \
    && rm -rf /tmp/tc

ENV PATH=/opt/cdp1802/bin:/opt/cdp1802/otp/bin:$PATH
ENV CDP1802_PREFIX=/opt/cdp1802
WORKDIR /work
