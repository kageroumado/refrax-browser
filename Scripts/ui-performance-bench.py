#!/usr/bin/env python3
"""Measure a macOS process's settled UI cost using kernel resource counters.

Choose a UI state, then run:
    python3 Scripts/ui-performance-bench.py PID --label islands --output islands.json

CPU percent uses one logical core as 100%. Counters come from proc_pid_rusage,
RUSAGE_INFO_V2, declared in the macOS SDK's sys/resource.h and libproc.h.
"""

import argparse
import ctypes
import datetime
import json
import math
import os
from pathlib import Path
import statistics
import time


class ResourceUsage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "user_time", "system_time", "package_idle_wakeups", "interrupt_wakeups",
            "pageins", "wired_size", "resident_size", "physical_footprint",
            "process_start", "process_exit", "child_user_time", "child_system_time",
            "child_package_idle_wakeups", "child_interrupt_wakeups", "child_pageins",
            "child_elapsed_time", "disk_bytes_read", "disk_bytes_written",
        )
    ]


LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
LIBPROC.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(ResourceUsage)]
LIBPROC.proc_pid_rusage.restype = ctypes.c_int


class Timebase(ctypes.Structure):
    _fields_ = [("numerator", ctypes.c_uint32), ("denominator", ctypes.c_uint32)]


TIMEBASE = Timebase()
LIBSYSTEM = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
LIBSYSTEM.mach_timebase_info.argtypes = [ctypes.POINTER(Timebase)]
LIBSYSTEM.mach_timebase_info.restype = ctypes.c_int
if LIBSYSTEM.mach_timebase_info(ctypes.byref(TIMEBASE)):
    raise RuntimeError("Could not read the Mach clock timebase")


def snapshot(pid):
    usage = ResourceUsage()
    if LIBPROC.proc_pid_rusage(pid, 2, ctypes.byref(usage)):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), f"PID {pid}")
    return {
        "time_ns": time.monotonic_ns(),
        "cpu_ns": (
            (usage.user_time + usage.system_time) * TIMEBASE.numerator // TIMEBASE.denominator
        ),
        "wakeups": usage.interrupt_wakeups,
        "package_idle_wakeups": usage.package_idle_wakeups,
        "footprint_bytes": usage.physical_footprint,
        "resident_bytes": usage.resident_size,
        "disk_bytes_written": usage.disk_bytes_written,
        "process_start": usage.process_start,
    }


def delta(before, after):
    if before["process_start"] != after["process_start"]:
        raise RuntimeError("The process restarted during measurement")
    seconds = (after["time_ns"] - before["time_ns"]) / 1e9
    return {
        "seconds": seconds,
        "cpu_percent": 100 * (after["cpu_ns"] - before["cpu_ns"]) / (seconds * 1e9),
        "wakeups_per_second": (after["wakeups"] - before["wakeups"]) / seconds,
        "package_idle_wakeups_per_second": (
            after["package_idle_wakeups"] - before["package_idle_wakeups"]
        ) / seconds,
        "footprint_mib": after["footprint_bytes"] / (1024 * 1024),
        "disk_bytes_written": after["disk_bytes_written"] - before["disk_bytes_written"],
    }


def self_check():
    before = snapshot(os.getpid())
    cpu_start = time.process_time_ns()
    while time.process_time_ns() - cpu_start < 200_000_000:
        math.sqrt(12345)
    elapsed = time.process_time_ns() - cpu_start
    after = snapshot(os.getpid())
    ratio = (after["cpu_ns"] - before["cpu_ns"]) / elapsed
    if not 0.95 < ratio < 1.05:
        raise RuntimeError(f"Kernel CPU counter calibration failed: ratio {ratio}")
    print(json.dumps({
        "kernel_counter_units": "Mach absolute ticks",
        "nanoseconds_per_tick": TIMEBASE.numerator / TIMEBASE.denominator,
        "calibration_ratio": ratio,
    }))


def measure(args):
    time.sleep(args.settle)
    samples = [snapshot(args.pid)]
    deadline = time.monotonic() + args.duration
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        time.sleep(min(args.interval, remaining))
        samples.append(snapshot(args.pid))
    intervals = [delta(a, b) for a, b in zip(samples, samples[1:])]
    total = delta(samples[0], samples[-1])
    cpu = sorted(item["cpu_percent"] for item in intervals)
    summary = {
        "label": args.label,
        **total,
        "cpu_p95_percent": cpu[math.ceil(len(cpu) * 0.95) - 1],
        "cpu_median_percent": statistics.median(cpu),
        "footprint_growth_mib": (
            samples[-1]["footprint_bytes"] - samples[0]["footprint_bytes"]
        ) / (1024 * 1024),
    }
    result = {
        "recorded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "pid": args.pid,
        "settle_seconds": args.settle,
        "cpu_percent_basis": "one logical core = 100%",
        "mach_timebase": [TIMEBASE.numerator, TIMEBASE.denominator],
        "summary": summary,
        "samples": samples,
        "intervals": intervals,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pid", type=int, nargs="?")
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--label", default="idle")
    parser.add_argument("--duration", type=float, default=20)
    parser.add_argument("--settle", type=float, default=5)
    parser.add_argument("--interval", type=float, default=1)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return
    if not args.pid or not args.output:
        parser.error("PID and --output are required for measurement")
    if (not all(math.isfinite(value) for value in (args.duration, args.interval, args.settle))
            or args.duration <= 0 or args.interval <= 0 or args.settle < 0):
        parser.error("Duration and interval must be positive; settle must be nonnegative")
    measure(args)


if __name__ == "__main__":
    main()
