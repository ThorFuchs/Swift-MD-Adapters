# Linux supervised worker

`Scripts/run-linux-supervised.py` is an **opt-in outer worker** for trusted
executables that process potentially untrusted input. Core and the Node adapter
APIs do not depend on it. It requires Linux, Python 3, `waitid(WNOWAIT)` and
permission to create processes and apply `RLIMIT_AS` and `RLIMIT_FSIZE`.

```sh
python3 Scripts/run-linux-supervised.py \
  --seconds 30 --memory-mib 8192 --file-mib 8 \
  --input-bytes 1000000 --output-bytes 2000000 --error-bytes 65536 -- \
  /absolute/path/to/swift-md --strict --highlight < input.md > output.html
```

An operator can add the documented trusted absolute Node/module options for
KaTeX and Pele. Supply input on stdin and capture the supervisor's stdout; do
not use `swift-md --output` or a worker input filename when relying on the
stream limits. File paths and commands passed to the worker, its environment,
Node executable and modules are trusted configuration. The shell redirection
in the example is performed by the invoking shell; use a temporary file plus
atomic rename if an existing destination must be preserved on failure.

The supervisor enforces a wall-clock deadline including stdin, byte limits on
stdin and both output streams while they are transferred, and per-process
address-space and individual-file-size limits inherited by ordinary children.
It buffers bounded stdout until the worker exits successfully; a worker failure,
interruption, deadline or stream overflow before delivery emits no stdout.
The deadline also applies when delivering completed output to a slow reader.
Once delivery starts, a broken or stalled downstream can still receive only a
prefix; stream writes are not transactional. Use an atomic file replacement
at the caller when all-or-nothing file output is required.
On a failure it sends SIGKILL to the worker's process group and waits up to one
second to reap its direct child. A process stuck in uninterruptible kernel work
may outlive that cleanup wait; synchronous process creation itself is not
deadline-interruptible. Exit 124 is used for a deadline and 125 for a
supervisor/limit error, but a worker can itself return those same codes; other
worker exit codes are propagated. Captured worker diagnostics are sent to
stderr when the worker itself fails; overflow and supervisor failures report
their own error. This applies only to stdout/stderr passing through the wrapper.

This is **not a security sandbox**. The resource limits are per process, not
an aggregate memory or filesystem quota. A descendant can deliberately enter a
new session, escape the process group and remain alive; the worker can access
whatever filesystem, network, credentials and privileges its account permits.
The supervisor inherits its environment, including Node-related variables.
Killing the supervisor itself with SIGKILL or a host crash cannot trigger
cleanup. A worker that writes files or opens its own network connections
bypasses the stream policy. Use a separately configured and tested OS sandbox
with cgroup v2 limits, restricted credentials, filesystem and network policies
for hostile executables or stronger tenant isolation. Do not infer those
properties from `RLIMIT_AS`, `RLIMIT_FSIZE`, or a process-group timeout.

The Linux CI gate runs boundary tests and an end-to-end CLI invocation with
real Swift highlighting, KaTeX and Pele. The existing legacy
`run-linux-constrained.sh` remains available with its narrower contract; the
two helpers do not silently wrap normal SwiftMD calls. Recheck behavior and
limits on the target host before relying on the worker in a deployment.

## Experimental systemd/cgroup worker

`run-linux-systemd.py` is a separate, opt-in profile for a host with systemd's
system manager and cgroup v2. It requires manager privileges. Install the
launcher, `run-linux-supervised.py`, and `systemd-worker-guard.py` together in
a root-owned, non-group/world-writable, world-readable directory outside
`/home`, `/root`, `/run/user`, and private temporary directories, such as
`/usr/libexec/swiftmd`. The launcher rejects unsafe installation ownership or modes.
Only an administrator should install and invoke these trusted scripts; do not
run a user-writable copy with `sudo`. The executable, its arguments, Node and
its modules must also be trusted and readable outside protected home folders.

```sh
sudo -n /usr/bin/python3 -I /usr/libexec/swiftmd/run-linux-systemd.py \
  --seconds 30 --memory-mib 1024 --tasks 128 --file-mib 8 --tmp-mib 32 -- \
  /usr/libexec/swiftmd/swift-md --strict --highlight < input.md > output.html
```

The launcher starts a uniquely named transient service as a dynamic unprivileged
user, in a private network namespace, with IPv6 socket creation restricted,
read-only system and cgroup mounts, protected home directories, and no effective
capabilities or new privileges. systemd applies cgroup-v2 memory, swap and task
limits, a service deadline and control-group termination, plus per-file and
temporary-filesystem size limits. The service's `TMPDIR` is a dedicated bounded
tmpfs under `/run`; `/tmp` and `/var/tmp` are inaccessible. It clears Node and dynamic-loader override
variables. The inner guard verifies the actual cgroup, limits, mount modes,
UID, privilege flags, IP socket restriction and temporary quotas **before** it
executes the worker; missing controls fail closed. The guard checks that the
namespace differs from the system manager's and has only `lo`; IPv4 loopback is
permitted because [Linux Foundation uses it for internal process wakeups](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/CoreFoundation/CFSocket.c).
The
stream supervisor provides
the bounded stdin/stdout/stderr contract above. A worker's arguments are sent to
the guard as structured data; document input remains on stdin.

This profile still requires a trustworthy host, systemd and kernel, and is not
an independent security certification. Read-only, world-readable host files
outside protected home directories may still be visible; AF_UNIX sockets and
other host interfaces are not a complete IPC policy. The worker shares the host
kernel. File-size limits are per file; assess other writable kernel interfaces
and deployment-specific paths.
A service started immediately before an uncatchable launcher kill may live until
its own systemd deadline. Uninterruptible kernel work can delay termination.
Do not use worker file input or `--output` when depending on the stream bounds.
Install only reviewed root-owned code; the privileged launcher is itself part of
the trusted computing base. Test this profile on each deployment host and do
not treat other platforms, service managers or container configurations as
validated merely because the code loads there.
Do not grant untrusted users unrestricted `sudo` access to this launcher: its
root-owned implementation and permitted worker arguments remain privileged
configuration even though the worker itself runs unprivileged.

On 2026-11-17, GitHub Actions run `44174154572` tested commit `36b6f6e` on
an `ubuntu-24.04` x86_64 hosted runner with systemd and cgroup v2. Its worker
job passed 12 stream-supervisor tests, three systemd isolation probes and eight
installed-worker tests, including the CLI with real Swift-Highlight, KaTeX and
Pele. The same run passed the core and Linux integration jobs. This evidence
applies to that runner and commit; it is not a security audit or evidence for
other hosts.
