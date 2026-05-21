# syntax=docker/dockerfile:1
#
# GRiSP Alloy builder image.
#
# Provides the Linux build environment used by the build-*.sh scripts as an
# alternative to the Vagrant VM. Package list mirrors Vagrantfile so behavior
# stays in parity with the VM.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C \
    USER=builder \
    HOME=/home/builder

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget sudo gosu locales \
        mc pv libncurses5-dev squashfs-tools \
        git bzr cvs mercurial subversion unzip bc \
        build-essential bison flex gperf texinfo help2man \
        libssl-dev gawk libtool-bin automake lzip python3 \
        mtools u-boot-tools git-lfs keyutils \
        qemu-user qemu-user-static \
        gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu \
        binutils-x86-64-linux-gnu-dbg \
        rsync cpio file; \
    locale-gen C.UTF-8 || true; \
    update-locale LC_ALL=C; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Builder user starts at UID/GID 1000; entrypoint remaps to host UID/GID
# so files written into bind-mounted /work and artefacts/ are owned correctly.
# Ubuntu 24.04 ships with a default 'ubuntu' user at 1000:1000; remove it so
# our 'builder' user can take that slot.
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupdel ubuntu 2>/dev/null || true; \
    groupadd -g 1000 builder && \
    useradd -m -u 1000 -g 1000 -s /bin/bash builder && \
    mkdir -p /opt/grisp_alloy_sdk && \
    chown -R builder:builder /opt/grisp_alloy_sdk

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
