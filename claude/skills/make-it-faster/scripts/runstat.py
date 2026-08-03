"""Run a command and report wall clock, CPU split, and peak RSS.

Replaces `/usr/bin/time -v`, which is NOT installed by default on Arch (verified
missing on this machine).

Two properties that matter for this skill:

- `ru_maxrss` is collected at wait() time, so it survives the child being SIGKILLed by
  the OOM killer. An OOM run still yields its peak memory.
- `cpu_fraction` is the I/O-bound gate: < 0.3 means the program is blocked on the
  network and a wall-clock A/B would be sampling the server, not the change. A value
  above 1 means multi-threaded compute, not an error.

Usage:
    python runstat.py -- <command> [args...]

stdout carries the metric line; the child's own stdout/stderr pass through untouched.
"""

import resource
import subprocess
import sys
import time

# ru_maxrss is kilobytes on Linux (getrusage(2)); reportedly bytes on macOS (unverified).
_RSS_KIB = sys.platform != "darwin"


def run(command: list[str]) -> int:
    """Execute a command and print its resource usage to stdout.

    Args:
        command: argv of the child process.

    Returns:
        The child's return code (negative if it was killed by a signal).
    """
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter()
    rc = subprocess.call(command)
    elapsed = time.perf_counter() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)

    user = after.ru_utime - before.ru_utime
    system = after.ru_stime - before.ru_stime
    maxrss_mb = after.ru_maxrss / (1024 if _RSS_KIB else 1024 * 1024)
    cpu_fraction = (user + system) / elapsed if elapsed > 0 else 0.0

    print(
        f"elapsed_s={elapsed:.3f} user_s={user:.3f} sys_s={system:.3f} "
        f"cpu_fraction={cpu_fraction:.3f} maxrss_mb={maxrss_mb:.1f} rc={rc}"
    )
    if rc == -9 or rc == 137:
        print(
            "NOTE: killed by SIGKILL (exit 137) — likely the OOM killer. "
            "maxrss_mb above is still valid and is the peak this run reached."
        )
    if cpu_fraction < 0.3:
        print(
            f"GATE: cpu_fraction {cpu_fraction:.3f} < 0.3 — I/O bound. Do not headline a "
            "wall-clock ratio; measure rows/bytes/round-trips instead."
        )
    return rc


if __name__ == "__main__":
    argv = sys.argv[1:]
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        sys.exit("usage: python runstat.py -- <command> [args...]")
    sys.exit(run(argv))
