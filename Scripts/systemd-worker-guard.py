#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fail closed unless the requested systemd worker controls are effective."""
import argparse
import base64
import errno
import json
import os
from pathlib import Path
import resource
import socket
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_limit(path):
    text = path.read_text().strip()
    return int(text) if text != 'max' else None


def mount_is_read_only(mount):
    options = [line.split()[5].split(',') for line in Path('/proc/self/mountinfo').read_text().splitlines()
               if line.split()[4] == mount]
    return bool(options) and 'ro' in options[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit', required=True)
    parser.add_argument('--memory-bytes', required=True, type=int)
    parser.add_argument('--tasks', required=True, type=int)
    parser.add_argument('--file-bytes', required=True, type=int)
    parser.add_argument('--tmp-bytes', required=True, type=int)
    parser.add_argument('--tmp-path', required=True)
    parser.add_argument('--host-net-inode', required=True, type=int)
    parser.add_argument('--command', required=True)
    args = parser.parse_args()
    require(bool(sys.flags.isolated), 'Python isolated mode is required')
    command = json.loads(base64.b64decode(args.command, validate=True))
    require(isinstance(command, list) and command and all(isinstance(x, str) for x in command), 'invalid command')
    require(Path(command[0]).is_absolute(), 'worker path must be absolute')
    require(os.geteuid() != 0 and os.getegid() != 0 and 0 not in os.getgroups(), 'worker must not run as root')
    status = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines() if ':' in line)
    require(status['NoNewPrivs'].strip() == '1' and
            all(int(status[name].strip(), 16) == 0 for name in ('CapEff', 'CapPrm', 'CapInh', 'CapAmb')),
            'worker privilege restrictions are not effective')
    require(not any(name in os.environ for name in ('NODE_OPTIONS', 'NODE_PATH', 'LD_PRELOAD', 'LD_LIBRARY_PATH')),
            'unsafe inherited environment override')
    groups = [line[3:] for line in Path('/proc/self/cgroup').read_text().splitlines() if line.startswith('0::')]
    require(len(groups) == 1 and groups[0].endswith('/' + args.unit), 'unexpected cgroup-v2 unit')
    group = Path('/sys/fs/cgroup') / groups[0].lstrip('/')
    memory = read_limit(group / 'memory.max')
    tasks = read_limit(group / 'pids.max')
    require(memory is not None and 0 < memory <= args.memory_bytes, 'cgroup memory limit missing')
    require(tasks is not None and 0 < tasks <= args.tasks, 'cgroup task limit missing')
    require(read_limit(group / 'memory.swap.max') == 0, 'cgroup swap limit missing')
    require(mount_is_read_only('/') and mount_is_read_only('/sys/fs/cgroup'), 'required read-only mounts missing')
    try:
        fd = os.open(group / 'cgroup.procs', os.O_WRONLY)
    except OSError as error:
        require(error.errno in (errno.EPERM, errno.EACCES, errno.EROFS), 'could not verify cgroup write restriction')
    else:
        os.close(fd)
        raise ValueError('worker can modify its cgroup')
    require(os.stat('/proc/self/ns/net').st_ino != args.host_net_inode, 'network namespace is not private')
    interfaces = {line.split(':', 1)[0].strip() for line in Path('/proc/net/dev').read_text().splitlines() if ':' in line}
    require(interfaces == {'lo'}, 'private network has unexpected interfaces')
    # Foundation on Linux uses IPv4 UDP loopback for Process wakeups.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
        receiver.settimeout(0.5)
        receiver.bind(('127.0.0.1', 0))
        sender.sendto(b'x', receiver.getsockname())
        require(receiver.recv(1) == b'x', 'private loopback is not operational')
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    except OSError as error:
        require(error.errno in (errno.EPERM, errno.EACCES, errno.EAFNOSUPPORT, errno.EPROTONOSUPPORT),
                'could not verify IPv6 socket restriction')
    else:
        sock.close()
        raise ValueError('IPv6 socket creation is not restricted')
    soft, hard = resource.getrlimit(resource.RLIMIT_FSIZE)
    require(0 < soft <= args.file_bytes and 0 < hard <= args.file_bytes, 'file-size limit missing')
    require(os.environ.get('TMPDIR') == args.tmp_path and Path(args.tmp_path).is_absolute(), 'temporary directory mismatch')
    filesystem = os.statvfs(args.tmp_path)
    require(0 < filesystem.f_blocks * filesystem.f_frsize <= args.tmp_bytes, 'temporary filesystem quota missing')
    require(not os.access('/tmp', os.W_OK) and not os.access('/var/tmp', os.W_OK),
            'unbounded temporary directory is writable')
    os.execv(command[0], command)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f'swiftmd systemd guard: {error}', file=sys.stderr)
        sys.exit(125)
