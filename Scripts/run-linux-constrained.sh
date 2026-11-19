#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Linux-only outer worker; RLIMIT_AS and RLIMIT_FSIZE apply per process.
set -eu
if [ "$(uname -s)" != Linux ]; then echo 'Linux with GNU timeout and prlimit is required' >&2; exit 2; fi
if [ "$#" -lt 5 ] || [ "$4" != '--' ]; then
  echo 'Usage: run-linux-constrained.sh SECONDS ADDRESS_SPACE_MIB FILE_MIB -- COMMAND [ARG...]' >&2
  exit 2
fi
seconds=$1 memory_mib=$2 file_mib=$3
for number in "$seconds" "$memory_mib" "$file_mib"; do
  case "$number" in ''|*[!0-9]*) echo 'Limits must be positive decimal integers' >&2; exit 2;; esac
done
[ "$seconds" -ge 1 ] && [ "$seconds" -le 3600 ] && [ "$memory_mib" -ge 1024 ] && [ "$memory_mib" -le 65536 ] && [ "$file_mib" -ge 1 ] && [ "$file_mib" -le 4096 ] || { echo 'Limits outside supported range' >&2; exit 2; }
command -v timeout >/dev/null && command -v prlimit >/dev/null || { echo 'GNU timeout and prlimit are required' >&2; exit 2; }
shift 4
# timeout normally creates a process group and sends KILL to that group. Descendants
# that deliberately leave the group are not contained; use a cgroup/sandbox for that.
exec timeout --signal=KILL "${seconds}s" prlimit --as="$((memory_mib * 1024 * 1024))" --fsize="$((file_mib * 1024 * 1024))" -- "$@"
