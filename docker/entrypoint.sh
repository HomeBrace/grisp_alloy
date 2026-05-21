#!/usr/bin/env bash
#
# Remap the in-image 'builder' user to the host UID/GID and exec the requested
# command as that user. Without this, files created in bind-mounted dirs would
# end up owned by an alien UID on the host.

set -e

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"

current_uid="$(id -u builder)"
current_gid="$(id -g builder)"

if [[ "$current_gid" != "$HOST_GID" ]]; then
    groupmod -o -g "$HOST_GID" builder
fi
if [[ "$current_uid" != "$HOST_UID" ]]; then
    usermod -o -u "$HOST_UID" builder
fi

# Named-volume mount points come up root-owned on first use; fix top-level
# ownership so builder can write into them. Non-recursive to keep this fast
# even when volumes are large.
for d in /opt/grisp_alloy_sdk /work/_cache /work/_build; do
    if [[ -d "$d" ]]; then
        chown builder:builder "$d" 2>/dev/null || true
    fi
done

# If invoked with no command, default to interactive bash.
if [[ $# -eq 0 ]]; then
    set -- bash
fi

exec env HOME=/home/builder USER=builder gosu builder "$@"
