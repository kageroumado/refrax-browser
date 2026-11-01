#!/usr/bin/env python3
"""Drives a private debug Refrax through real input and checks what happened.

Each scenario sets state up through refrax-ctl, acts through rocuronium (one `plan` per
sequence, so a run of clicks, keys and drags reaches the app with no round trips), and checks
the result through refrax-ctl and a screenshot. The instance runs under its own home
(CFFIXED_USER_HOME), so its store, control socket and engines are its own and the debug app a
person is using is untouched; rocuronium reaches it by pid.

    Scripts/drive/drive.py launch                 start (or restart) the private instance
    Scripts/drive/drive.py run [ids or prefixes]   run scenarios, e.g. `run B` or `run B14 E60`
    Scripts/drive/drive.py list                    list scenarios
    Scripts/drive/drive.py ctl <args…>             refrax-ctl against the private instance
    Scripts/drive/drive.py quit

Drags and held keys take the real cursor, so rocuronium asks the person at the Mac first
(hold A once to allow 30 minutes of them) or runs them freely when nobody is there.
Reports and screenshots go to $DRIVE_OUT (default /Volumes/Ugreen/Scratch/drive/<run>).
"""

from __future__ import annotations

import glob
import importlib.util
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path(os.environ.get("DRIVE_HOME", "/Volumes/Ugreen/Scratch/drive-home"))
OUT_ROOT = Path(os.environ.get("DRIVE_OUT", "/Volumes/Ugreen/Scratch/drive"))
BUNDLE_ID = "website.refrax.browser.debug"
SUPPORT = HOME / "Library/Application Support" / BUNDLE_ID
PID_FILE = HOME / "drive.pid"


def products() -> Path:
    if path := os.environ.get("REFRAX_PRODUCTS"):
        return Path(path)
    found = sorted(glob.glob(os.path.expanduser("/Volumes/Ugreen/Build/DerivedData/Refrax-*/Build/Products/Debug")))
    found += sorted(glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/Refrax-*/Build/Products/Debug")))
    if not found:
        sys.exit("drive: no debug build found; run refraxbuild or set REFRAX_PRODUCTS")
    return Path(found[0])


APP_BINARY = products() / "Refrax.app/Contents/MacOS/Refrax"
CTL_BINARY = products() / "refrax-ctl"


class DriveError(Exception):
    pass


# MARK: - The instance


def environment() -> dict[str, str]:
    env = dict(os.environ)
    env["CFFIXED_USER_HOME"] = str(HOME)
    return env


def running_pid() -> int | None:
    try:
        pid = int(PID_FILE.read_text())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


def launch(*, in_memory: bool = True) -> int:
    quit_instance()
    SUPPORT.mkdir(parents=True, exist_ok=True)
    engines = SUPPORT / "Engines"
    if not engines.exists():
        source = Path.home() / "Library/Application Support" / BUNDLE_ID / "Engines"
        if source.exists():
            subprocess.run(["cp", "-R", str(source), str(engines)], check=True)
    args = [str(APP_BINARY)] + (["--in-memory"] if in_memory else [])
    log = open(HOME / "app.log", "w")
    process = subprocess.Popen(args, env=environment(), stdout=log, stderr=log, start_new_session=True)
    PID_FILE.write_text(str(process.pid))
    deadline = time.time() + 120
    while time.time() < deadline:
        if ctl_ok("ping"):
            # `ping` needs no authorization; the first real request raises the access prompt.
            for _ in range(40):
                if ctl_ok("tab", "list"):
                    break
                allow_harness_client()
                time.sleep(0.5)
            time.sleep(1)
            park()
            return process.pid
        allow_harness_client()
        time.sleep(0.5)
    raise DriveError("the private instance never answered refrax-ctl ping (see drive-home/app.log)")


def allow_harness_client() -> None:
    """Answers the private instance's control-access prompt for the harness's own refrax-ctl.

    The instance asks once per client identity; the prompt is a modal that blocks the app,
    and it belongs to this instance alone (its own home and settings).
    """
    found = roc("find", "--pid", str(pid()), "--label", "Always Allow", "--role", "AXButton")
    if found.get("matches"):
        roc("click", "--pid", str(pid()), "--label", "Always Allow", "--role", "AXButton",
            "--why", "allow the harness's refrax-ctl in the private test copy")


def park() -> None:
    """Moves the instance's windows onto rocuronium's virtual display, off the person's screen.

    A move right after launch is clamped by the window manager, so it is tried a few times.
    """
    for _ in range(6):
        roc("park", "--pid", str(pid()))
        windows = roc("windows", "--pid", str(pid())).get("windows", [])
        if windows and all(w.get("onVirtualDisplay") for w in windows if not w.get("minimized")):
            return
        time.sleep(1)
    print("drive: the window could not be parked; it stays on the main display", file=sys.stderr)


def quit_instance() -> None:
    if pid := running_pid():
        os.kill(pid, signal.SIGTERM)
        for _ in range(40):
            try:
                os.kill(pid, 0)
            except OSError:
                break
            time.sleep(0.25)
        else:
            os.kill(pid, signal.SIGKILL)
    PID_FILE.unlink(missing_ok=True)


def pid() -> int:
    if found := running_pid():
        return found
    raise DriveError("no private instance; run `drive.py launch`")


# MARK: - refrax-ctl


def ctl_raw(*args: str, timeout: float = 60) -> subprocess.CompletedProcess:
    return subprocess.run([str(CTL_BINARY), *args], env=environment(), capture_output=True, text=True, timeout=timeout)


def ctl_ok(*args: str) -> bool:
    try:
        return ctl_raw(*args, timeout=5).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def ctl(*args: str, timeout: float = 60) -> str:
    result = ctl_raw(*args, timeout=timeout)
    if result.returncode != 0:
        raise DriveError(f"refrax-ctl {' '.join(args)}: {(result.stderr or result.stdout).strip()}")
    return result.stdout.strip()


def ctl_json(*args: str, timeout: float = 60):
    result = ctl_raw(*args, "--json", timeout=timeout)
    text = (result.stderr.strip() or result.stdout.strip())
    if result.returncode != 0:
        raise DriveError(f"refrax-ctl {' '.join(args)}: {text}")
    start = text.find("{")
    return json.loads(text[start:]).get("data", {})


def page_exec(script: str, tab: str | None = None):
    args = ["page", "exec", script] + (["--tab", tab] if tab else [])
    return ctl(*args)


# MARK: - rocuronium


def roc(verb: str, *args: str, timeout: float = 120) -> dict:
    result = subprocess.run(["rocuronium", verb, *args, "--json"], capture_output=True, text=True, timeout=timeout)
    text = result.stdout.strip() or result.stderr.strip()
    try:
        return json.loads(text[text.find("{"):])
    except (ValueError, IndexError):
        raise DriveError(f"rocuronium {verb}: {text[:400]}")


def plan(steps: list[dict], *, profile: str = "ghost") -> dict:
    """Runs `steps` as one rocuronium plan against the private instance; each step gets its pid."""
    for step in steps:
        step.setdefault("pid", pid())
    reply = subprocess.run(
        ["rocuronium", "plan", "--json"], input=json.dumps({"profile": profile, "steps": steps}),
        capture_output=True, text=True, timeout=300,
    )
    text = reply.stdout.strip() or reply.stderr.strip()
    try:
        return json.loads(text[text.find("{"):])
    except (ValueError, IndexError):
        raise DriveError(f"rocuronium plan: {text[:400]}")


def main_window() -> dict:
    """The private instance's browser window frame, in screen points (top-left origin)."""
    windows = roc("windows", "--pid", str(pid())).get("windows", [])
    browser = [w for w in windows if not w.get("minimized")]
    if not browser:
        raise DriveError("the private instance has no window")
    return max(browser, key=lambda w: w["frame"]["w"] * w["frame"]["h"])["frame"]


def to_screen(point: tuple[float, float]) -> tuple[float, float]:
    """A point in the browser window's content (top-left origin) as a screen point."""
    frame = main_window()
    return frame["x"] + point[0], frame["y"] + point[1]


def screenshot(name: str) -> Path:
    """The private instance's windows as a PNG in the scenario's folder.

    rocuronium writes captures only to a few folders (/tmp among them), so the file is
    captured there and moved.
    """
    staging = Path("/tmp/refrax-drive") / f"{os.getpid()}-{name}.png"
    staging.parent.mkdir(exist_ok=True)
    reply = roc("screenshot", "--pid", str(pid()), "--path", str(staging))
    if not reply.get("ok", True) or not staging.exists():
        raise DriveError(f"screenshot {name}: {reply.get('error') or reply.get('summary')}")
    path = Scenario.current_out / f"{name}.png"
    shutil.move(staging, path)
    return path


def wait(seconds: float) -> None:
    time.sleep(seconds)


def until(check, *, seconds: float = 8, every: float = 0.25, message: str = "condition"):
    deadline = time.time() + seconds
    last = None
    while time.time() < deadline:
        try:
            last = check()
            if last:
                return last
        except DriveError:
            pass
        time.sleep(every)
    raise DriveError(f"timed out waiting for {message} (last: {last!r})")


# MARK: - Scenarios


@dataclass
class Scenario:
    id: str
    title: str
    run: callable
    needs_cursor: bool = False
    fresh: bool = False

    current_out: Path = field(default=OUT_ROOT, init=False, repr=False)


REGISTRY: list[Scenario] = []


def scenario(id: str, title: str, *, needs_cursor: bool = False, fresh: bool = False):
    def register(function):
        REGISTRY.append(Scenario(id, title, function, needs_cursor, fresh))
        return function

    return register


class Check:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.notes: list[str] = []

    def expect(self, condition, message: str) -> bool:
        if not condition:
            self.failures.append(message)
        return bool(condition)

    def note(self, message: str) -> None:
        self.notes.append(message)


def load_scenarios() -> None:
    # Scenario files `import drive`; run as a script this module is `__main__`, so the name
    # must resolve to it, or they would register into a second copy.
    sys.modules.setdefault("drive", sys.modules[__name__])
    for path in sorted((HERE / "scenarios").glob("*.py")):
        spec = importlib.util.spec_from_file_location(f"drive_scenarios.{path.stem}", path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)


def selected(patterns: list[str]) -> list[Scenario]:
    if not patterns:
        return list(REGISTRY)
    return [s for s in REGISTRY if any(s.id == p or s.id.startswith(p) for p in patterns)]


def run(patterns: list[str]) -> int:
    load_scenarios()
    chosen = selected(patterns)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = OUT_ROOT / stamp
    out.mkdir(parents=True, exist_ok=True)
    if not running_pid():
        launch()
    lines = [f"# Drive run {stamp}", "", "| id | result | title | detail |", "|---|---|---|---|"]
    failed = 0
    for item in chosen:
        Scenario.current_out = out / item.id
        Scenario.current_out.mkdir(exist_ok=True)
        if item.fresh:
            launch()
        check = Check()
        started = time.time()
        try:
            item.run(check)
            result = "pass" if not check.failures else "FAIL"
        except DriveError as error:
            check.failures.append(f"error: {error}")
            result = "ERROR"
        except Exception:
            check.failures.append(traceback.format_exc(limit=3).replace("\n", " "))
            result = "ERROR"
        failed += result != "pass"
        detail = "; ".join(check.failures + check.notes).replace("|", "/")
        lines.append(f"| {item.id} | {result} | {item.title} | {detail} |")
        print(f"{item.id:6} {result:5} {time.time() - started:5.1f}s  {item.title}  {detail[:160]}", flush=True)
    (out / "report.md").write_text("\n".join(lines) + "\n")
    print(f"\nreport: {out / 'report.md'}")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    command, *rest = argv or ["list"]
    if command == "launch":
        print(f"private instance pid {launch(in_memory='--keep' not in rest)}")
    elif command == "quit":
        quit_instance()
    elif command == "list":
        load_scenarios()
        for item in REGISTRY:
            print(f"{item.id:6} {'cursor ' if item.needs_cursor else '       '}{item.title}")
    elif command == "run":
        return run(rest)
    elif command == "ctl":
        result = ctl_raw(*rest)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
