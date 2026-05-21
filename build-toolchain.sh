#!/usr/bin/env bash

# build-toolchain.sh - GRiSP Alloy Toolchain Builder
#
# DEVELOPER OVERVIEW:
# Builds cross-compilation toolchain for embedded targets using crosstool-NG.
# The toolchain includes GCC, binutils, glibc/musl, and other essential tools
# needed to compile software for the target architecture.
#
# HIGH-LEVEL FLOW:
# 1. Parse arguments and handle Vagrant VM execution if needed
# 2. Load target-specific toolchain configuration (defconfig)
# 3. Delegate to appropriate toolchain build script (e.g., build-crosstool-ng.sh)
#
# OUTPUT:
# - Cross-compilation toolchain in GLB_TOOLCHAIN_DIR
# - Compressed toolchain archive in artefacts/

set -e

ARGS=( "$@" )

show_usage()
{
    echo "USAGE: build-toolchain.sh [-h] [-d] [-c] [-V] [-D] [-P] [-K] TARGET"
    echo "OPTIONS:"
    echo " -h Show this"
    echo " -d Print scripts debug information"
    echo " -c Cleanup the curent state and start building from scratch"
    echo " -V Using the Vagrant VM even on Linux (mutually exclusive with -D)"
    echo " -D Run the build inside the Docker builder image (mutually exclusive with -V)"
    echo " -P Re-provision the Vagrant VM, or rebuild the Docker image when used with -D"
    echo " -K Keep the Vagrant VM running after exiting (no effect with -D)"
    echo
    echo "e.g. build-toolchain.sh grisp2"
}

# Parse script's arguments
OPTIND=1
ARG_TARGET=""
ARG_DEBUG="${DEBUG:-0}"
ARG_CLEAN=false
ARG_FORCE_VAGRANT=false
ARG_FORCE_DOCKER=false
ARG_PROVISION_VAGRANT=false
ARG_KEEP_VAGRANT=false
while getopts "hdcVDPK" opt; do
    case "$opt" in
    d)
        ARG_DEBUG=1
        ;;
    c)
        ARG_CLEAN=true
        ;;
    V)
        ARG_FORCE_VAGRANT=true
        ;;
    D)
        ARG_FORCE_DOCKER=true
        ;;
    P)
        ARG_PROVISION_VAGRANT=true
        ;;
    K)
        ARG_KEEP_VAGRANT=true
        ;;
    *)
        show_usage
        exit 0
        ;;
    esac
done
shift $((OPTIND-1))
[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
    echo "ERROR: Missing arguments"
    show_usage
    exit 1
fi
ARG_TARGET="$1"
shift
if [[ $# > 0 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

# Load common variables and functions
source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"
set_debug_level "$ARG_DEBUG"

if [[ $ARG_FORCE_DOCKER == true && $ARG_FORCE_VAGRANT == true ]]; then
    error 1 "-D and -V are mutually exclusive"
fi

# Decide execution mode. Docker only runs on explicit -D for now; Vagrant
# stays the implicit default on non-Linux hosts to keep existing flows working.
if [[ $ARG_FORCE_DOCKER == true ]]; then
    USE_DOCKER=true
    USE_VAGRANT=false
elif [[ $ARG_FORCE_VAGRANT == true || $HOST_OS != "linux" ]]; then
    USE_DOCKER=false
    USE_VAGRANT=true
else
    USE_DOCKER=false
    USE_VAGRANT=false
fi

# DOCKER EXECUTION BLOCK
if [[ $USE_DOCKER == true ]]; then
    cd "$GLB_TOP_DIR"
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        "${GLB_TOP_DIR}/docker/build-image.sh" --no-cache
    fi
    NEW_ARGS=( )
    if [[ $ARG_DEBUG -gt 0 ]]; then
        NEW_ARGS+=( "-d" )
    fi
    if [[ $ARG_CLEAN == true ]]; then
        NEW_ARGS+=( "-c" )
    fi
    NEW_ARGS+=( "$ARG_TARGET" )
    DOCKER_EXTRA_MOUNTS=()
    DOCKER_EXTRA_ENV=()
    run_in_docker "build-toolchain.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# VAGRANT VM EXECUTION BLOCK
# Toolchain builds require Linux, so non-Linux hosts use VM
if [[ $USE_VAGRANT == true ]]; then
    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    NEW_ARGS=( )
    if [[ $ARG_DEBUG -gt 0 ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-d" )
    fi
    if [[ $ARG_CLEAN == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-c" )
    fi
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )
    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-toolchain.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE
# Load target-specific toolchain configuration
TOOLCHAIN_DEFCONFIG="$GLB_TOOLCHAIN_DIR/configs/${GLB_TARGET_NAME}_${BUILD_OS}_${BUILD_ARCH}_defconfig"

if [[ ! -e $TOOLCHAIN_DEFCONFIG ]]; then
    error 1 "Cannot find toolchain configuration $TOOLCHAIN_DEFCONFIG"
fi

# Extract toolchain type from config (e.g., "crosstool-ng")
TOOLCHAIN=$( read_defconfig_key $TOOLCHAIN_DEFCONFIG GLB_TOOLCHAIN_TYPE )

# Find and execute appropriate toolchain build script
TOOLCHAIN_BUILD_SCRIPT="${GLB_TOOLCHAIN_SCRIPT_DIR}/build-${TOOLCHAIN}.sh"
if [[ ! -x $TOOLCHAIN_BUILD_SCRIPT ]]; then
    error 1 "Cannot find toolchain build script $TOOLCHAIN_BUILD_SCRIPT"
fi

# Execute toolchain-specific build script with configuration
CLEAN=$ARG_CLEAN GLB_TOP_DIR="${GLB_TOP_DIR}" $TOOLCHAIN_BUILD_SCRIPT "$GLB_TARGET_NAME" "$TOOLCHAIN_DEFCONFIG"
