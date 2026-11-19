#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run a trusted Linux worker with bounded streams, time and per-process limits.

This is not a sandbox: descendants can leave the process group and filesystem,
network, aggregate memory and privileges are not isolated.
"""
import argparse
import fcntl
import os
from pathlib import Path
import resource
import select
import signal
import subprocess
import sys
import time

CHUNK = 65_536


class WorkerError(Exception):
    def __init__(self, message, code=125):
        super().__init__(message)
        self.code = code


def deliver(stdout, stderr, deadline):
    """Write only completed output, without hanging on a stalled downstream."""
    streams = [(sys.stdout.fileno(), stdout), (sys.stderr.fileno(), stderr)]
    original = [(fd, fcntl.fcntl(fd, fcntl.F_GETFL)) for fd, _ in streams]
    try:
        for fd, flags in original:
            fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        positions = [0, 0]
        while any(positions[index] < len(data) for index, (_, data) in enumerate(streams)):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise WorkerError('output delivery deadline exceeded', 124)
            poller = select.poll()
            for index, (fd, data) in enumerate(streams):
                if positions[index] < len(data):
                    poller.register(fd, select.POLLOUT | select.POLLERR | select.POLLHUP)
            for fd, _ in poller.poll(max(1, min(100, int(remaining * 1000)))):
                index = 0 if fd == streams[0][0] else 1
                try:
                    written = os.write(fd, memoryview(streams[index][1])[positions[index]:positions[index] + CHUNK])
                    positions[index] += written
                except BlockingIOError:
                    continue
    finally:
        for fd, flags in original:
            try:
                fcntl.fcntl(fd, fcntl.F_SETFL, flags)
            except OSError:
                pass


def report(message):
    """Do not let an unread diagnostic pipe defeat a deadline."""
    fd = sys.stderr.fileno()
    try:
        original = fcntl.fcntl(fd, fcntl.F_GETFL)
        try:
            fcntl.fcntl(fd, fcntl.F_SETFL, original | os.O_NONBLOCK)
            os.write(fd, f'swiftmd supervisor: {message}\n'.encode('utf-8', 'replace'))
        finally:
            fcntl.fcntl(fd, fcntl.F_SETFL, original)
    except OSError:
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=30)
    parser.add_argument('--memory-mib', type=int, default=8192)
    parser.add_argument('--file-mib', type=int, default=8)
    parser.add_argument('--input-bytes', type=int, default=1_000_000)
    parser.add_argument('--output-bytes', type=int, default=2_000_000)
    parser.add_argument('--error-bytes', type=int, default=65_536)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if sys.platform != 'linux':
        parser.error('Linux is required')
    if not args.command or args.command[0] != '--' or len(args.command) < 2:
        parser.error('specify -- followed by an absolute trusted executable and its arguments')
    command = args.command[1:]
    if not Path(command[0]).is_absolute():
        parser.error('worker executable must be an absolute path')
    if not (1 <= args.seconds <= 3600 and 1024 <= args.memory_mib <= 65536 and 1 <= args.file_mib <= 4096):
        parser.error('time, memory or file limit is outside the supported range')
    if any(value < 1 or value > 64_000_000 for value in (args.input_bytes, args.output_bytes, args.error_bytes)):
        parser.error('stream limits must be between 1 and 64000000 bytes')

    def interrupted(signum, _frame):
        raise WorkerError(f'interrupted by signal {signum}', 128 + signum)

    # Standalone, single-threaded process: preexec_fn applies limits before exec.
    signal.signal(signal.SIGTERM, interrupted)
    process = None
    old_flags = None
    out, err = bytearray(), bytearray()
    deadline = time.monotonic() + args.seconds
    try:
        # Do not lose a child if a termination signal arrives during Popen.
        # The worker's original signal mask is restored before its exec.
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
        def set_limits():
            try:
                for key, limit in ((resource.RLIMIT_AS, args.memory_mib * 1024 * 1024),
                                   (resource.RLIMIT_FSIZE, args.file_mib * 1024 * 1024)):
                    resource.setrlimit(key, (limit, limit))
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        try:
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, start_new_session=True,
                                       preexec_fn=set_limits, bufsize=0)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        stdin = sys.stdin.fileno()
        old_flags = fcntl.fcntl(stdin, fcntl.F_GETFL)
        fcntl.fcntl(stdin, fcntl.F_SETFL, old_flags | os.O_NONBLOCK)
        incoming = process.stdin.fileno()
        outgoing = process.stdout.fileno()
        errors = process.stderr.fileno()
        for fd in (incoming, outgoing, errors):
            os.set_blocking(fd, False)
        pending = bytearray()
        input_eof = False
        input_count = 0
        output_open, error_open, child_input_open = True, True, True
        child_exited = False

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise WorkerError('worker deadline exceeded', 124)
            if input_eof and not pending and child_input_open:
                process.stdin.close()
                child_input_open = False
            poller = select.poll()
            if not input_eof and not pending:
                poller.register(stdin, select.POLLIN | select.POLLHUP | select.POLLERR)
            if pending and child_input_open:
                poller.register(incoming, select.POLLOUT | select.POLLHUP | select.POLLERR)
            if output_open:
                poller.register(outgoing, select.POLLIN | select.POLLHUP | select.POLLERR)
            if error_open:
                poller.register(errors, select.POLLIN | select.POLLHUP | select.POLLERR)
            for fd, _event in poller.poll(max(1, min(100, int(remaining * 1000)))):
                if fd == stdin:
                    try:
                        data = os.read(stdin, CHUNK)
                    except BlockingIOError:
                        continue
                    if data:
                        input_count += len(data)
                        if input_count > args.input_bytes:
                            raise WorkerError('input limit exceeded')
                        pending.extend(data)
                    else:
                        input_eof = True
                elif fd == incoming:
                    try:
                        written = os.write(incoming, pending)
                        del pending[:written]
                    except BlockingIOError:
                        continue
                    except BrokenPipeError:
                        raise WorkerError('worker closed input before it was consumed') from None
                else:
                    try:
                        data = os.read(fd, CHUNK)
                    except BlockingIOError:
                        continue
                    if not data:
                        if fd == outgoing: output_open = False
                        else: error_open = False
                    else:
                        target, maximum = (out, args.output_bytes) if fd == outgoing else (err, args.error_bytes)
                        if len(target) + len(data) > maximum:
                            raise WorkerError('stdout limit exceeded' if fd == outgoing else 'stderr limit exceeded')
                        target.extend(data)
            if input_eof and not pending and child_input_open:
                process.stdin.close()
                child_input_open = False
            # WNOWAIT retains the child PID until cleanup. This avoids signalling
            # a recycled process-group ID after reaping the group leader.
            if not child_exited and os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None:
                child_exited = True
                if not input_eof or pending:
                    raise WorkerError('worker exited before consuming the complete input')
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if child_exited and not output_open and not error_open:
                break
        result = process.wait()
        if result != 0:
            deliver(b'', err, deadline)
            return result if result > 0 else 128 - result
        deliver(out, err, deadline)
        return 0
    finally:
        if old_flags is not None:
            try:
                fcntl.fcntl(sys.stdin.fileno(), fcntl.F_SETFL, old_flags)
            except OSError:
                pass
        if process is not None:
            # The leader is unreaped until here on every failure path.
            if process.returncode is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    report('worker did not exit within the cleanup grace period')
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None:
                    stream.close()


if __name__ == '__main__':
    try:
        sys.exit(main())
    except WorkerError as error:
        report(error)
        sys.exit(error.code)
    except KeyboardInterrupt:
        report('interrupted')
        sys.exit(130)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report(error)
        sys.exit(125)
