#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run a trusted SwiftMD worker in a guarded systemd/cgroup-v2 service."""
import argparse
import base64
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import uuid

HERE = Path(__file__).resolve().parent


class LauncherError(Exception):
    def __init__(self, message, code=125):
        super().__init__(message)
        self.code = code


def root_controlled(path):
    """Require a root-owned, non-writable installation accessible to DynamicUser."""
    path = path.resolve(strict=True)
    for item in (path, *path.parents):
        info = item.stat()
        if info.st_uid != 0 or info.st_mode & 0o022:
            raise LauncherError(f'installation path is not root-controlled: {item}')
        if item == path:
            if not stat.S_ISREG(info.st_mode) or not info.st_mode & 0o004:
                raise LauncherError(f'installation file must be world-readable: {item}')
        elif not stat.S_ISDIR(info.st_mode) or not info.st_mode & 0o001:
            raise LauncherError(f'installation directory must be traversable: {item}')
    return path


def stop_unit(unit):
    stop = subprocess.run(['/usr/bin/systemctl', '--quiet', 'stop', unit],
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, timeout=5)
    if stop.returncode == 0:
        return
    status = subprocess.run(['/usr/bin/systemctl', 'show', '--property=LoadState', '--value', unit],
                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
    if status.stdout.strip() != 'not-found':
        raise LauncherError(f'could not confirm cleanup of unit {unit}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=30)
    parser.add_argument('--memory-mib', type=int, default=1024)
    parser.add_argument('--tasks', type=int, default=128)
    parser.add_argument('--file-mib', type=int, default=8)
    parser.add_argument('--tmp-mib', type=int, default=32)
    parser.add_argument('--input-bytes', type=int, default=1_000_000)
    parser.add_argument('--output-bytes', type=int, default=2_000_000)
    parser.add_argument('--error-bytes', type=int, default=65_536)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if sys.platform != 'linux' or os.geteuid() != 0 or not sys.flags.isolated:
        parser.error('Linux, system-manager privileges and Python isolated mode (-I) are required')
    if not args.command or args.command[0] != '--' or len(args.command) < 2:
        parser.error('specify -- followed by a trusted executable and its arguments')
    command = args.command[1:]
    if not Path(command[0]).is_absolute():
        parser.error('worker executable must be an absolute path')
    if not (1 <= args.seconds <= 1800 and 128 <= args.memory_mib <= 16384 and 16 <= args.tasks <= 1024
            and 1 <= args.file_mib <= 4096 and 4 <= args.tmp_mib <= 4096):
        parser.error('resource limit outside supported range')
    if any(value < 1 or value > 64_000_000 for value in (args.input_bytes, args.output_bytes, args.error_bytes)):
        parser.error('stream limits must be between 1 and 64000000 bytes')
    encoded = base64.b64encode(json.dumps(command, ensure_ascii=True).encode()).decode()
    if len(encoded) > 32768:
        parser.error('command arguments exceed the supported size')
    root_controlled(Path(__file__))
    supervisor = root_controlled(HERE / 'run-linux-supervised.py')
    guard = root_controlled(HERE / 'systemd-worker-guard.py')
    with tempfile.TemporaryDirectory(prefix='swiftmd-worker-', dir='/run') as work:
        return launch(args, encoded, supervisor, guard, work)


def launch(args, encoded, supervisor, guard, work):
    unit = 'swiftmd-' + uuid.uuid4().hex + '.service'
    properties = (
        'DynamicUser=yes', 'NoNewPrivileges=yes', 'CapabilityBoundingSet=',
        'PrivateNetwork=yes', 'RestrictAddressFamilies=AF_UNIX AF_INET',
        'ProtectSystem=strict', 'ProtectHome=yes', 'ProtectControlGroups=yes',
        'PrivateDevices=yes', 'RestrictNamespaces=yes',
        'MemoryAccounting=yes', f'MemoryMax={args.memory_mib}M', 'MemorySwapMax=0',
        'TasksAccounting=yes', f'TasksMax={args.tasks}', f'LimitFSIZE={args.file_mib}M',
        f'TemporaryFileSystem={work}:rw,nosuid,nodev,size={args.tmp_mib}M,mode=1777',
        'InaccessiblePaths=/tmp /var/tmp', f'Environment=TMPDIR={work}',
        'UnsetEnvironment=NODE_OPTIONS NODE_PATH LD_PRELOAD LD_LIBRARY_PATH',
        'KillMode=control-group', 'KillSignal=SIGKILL', 'TimeoutStopSec=1s',
        f'TimeoutStartSec={args.seconds}s', f'RuntimeMaxSec={args.seconds}s',
    )
    systemd = ['/usr/bin/systemd-run', '--system', '--quiet', '--wait', '--pipe', '--collect',
               '--service-type=exec', '--unit', unit]
    for prop in properties:
        systemd.extend(('--property', prop))
    systemd.extend(('--', '/usr/bin/python3', '-I', str(guard), '--unit', unit,
                    '--memory-bytes', str(args.memory_mib * 1024 * 1024), '--tasks', str(args.tasks),
                    '--file-bytes', str(args.file_mib * 1024 * 1024),
                    '--tmp-bytes', str(args.tmp_mib * 1024 * 1024), '--tmp-path', work,
                    '--host-net-inode', str(os.stat('/proc/1/ns/net').st_ino), '--command', encoded))
    wrapped = ['/usr/bin/python3', '-I', str(supervisor), '--seconds', str(args.seconds + 10),
               '--memory-mib', '8192', '--file-mib', '4096', '--input-bytes', str(args.input_bytes),
               '--output-bytes', str(args.output_bytes), '--error-bytes', str(args.error_bytes), '--', *systemd]

    def interrupted(signum, _frame):
        raise LauncherError(f'interrupted by signal {signum}', 128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    child = None
    unit_may_exist = False
    try:
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
        try:
            # Restore the inherited mask in the child before it execs Python.
            child = subprocess.Popen(wrapped, start_new_session=True,
                                     preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, old_mask))
            unit_may_exist = True
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        result = child.wait()
        return result if result >= 0 else 128 - result
    finally:
        try:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=1)
        finally:
            if unit_may_exist:
                stop_unit(unit)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except LauncherError as error:
        print(f'swiftmd systemd launcher: {error}', file=sys.stderr)
        sys.exit(error.code)
    except KeyboardInterrupt:
        print('swiftmd systemd launcher: interrupted', file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'swiftmd systemd launcher: {error}', file=sys.stderr)
        sys.exit(125)
