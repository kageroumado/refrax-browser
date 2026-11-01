"""Islands, keyboard, Shields and Chromium scenarios, numbered after the test-drive list
(Docs/plans/test-drive-2026-11-01.md)."""

import os
import time

import drive
from drive import scenario

PAGES = [
    "https://example.com",
    "https://en.wikipedia.org/wiki/WebKit",
    "https://en.wikipedia.org/wiki/Swift_(programming_language)",
    "https://github.com",
    "https://news.ycombinator.com",
]
FORM = "data:text/html,<title>Form</title><input id=q autofocus><p>form page</p>"
YOUTUBE = "https://www.youtube.com/watch?v=dfW-qT9mOjQ"
AD_PROBE = (
    'JSON.stringify((()=>{const p=document.querySelector("#movie_player");'
    "const r=p&&p.getPlayerResponse?p.getPlayerResponse():null;"
    'return {ads:r&&r.adPlacements?r.adPlacements.length:0, showing:!!document.querySelector(".ad-showing")}})())'
)


# MARK: - Helpers


def islands() -> dict:
    return drive.ctl_json("islands", "state")


def rows() -> list[dict]:
    return [row for island in islands()["islands"] for row in island["rows"]]


def row_titled(prefix: str) -> dict:
    return next(row for row in rows() if row["title"].startswith(prefix))


def open_pages(urls=PAGES) -> None:
    for url in urls:
        drive.ctl("open", url)
    time.sleep(3)


def latch() -> None:
    drive.ctl("islands", "show")
    drive.until(lambda: islands()["isRevealed"], message="islands latched")


def press(label: str, why: str) -> dict:
    """An accessibility press on the element labeled `label` in the private instance."""
    return drive.roc("click", "--pid", str(drive.pid()), "--label", label, "--role", "AXButton", "--why", why)


def keys(*sequence: str, why: str = "browse the islands with the keyboard") -> dict:
    """Keys typed into the private instance, made the active app first: AppKit hands key
    events to the key window, which an inactive app has none of, so this takes the keyboard."""
    steps = [{"command": "activate", "why": "type into the private test copy"}]
    for item in sequence:
        if item.startswith("text:"):
            steps.append({"command": "type", "text": item[5:], "why": why})
        else:
            steps.append({"command": "key", "keys": item, "why": why})
    return drive.plan(steps, profile="visible")


def cursor_allowed(check) -> bool:
    if os.environ.get("DRIVE_CURSOR") == "1":
        return True
    check.note("skipped: needs the real cursor (run with DRIVE_CURSOR=1 while away, or hold A)")
    return False


def drag(start: tuple[float, float], end: tuple[float, float], why: str) -> dict:
    """A real-cursor drag between two window points, as one plan step."""
    a, b = drive.to_screen(start), drive.to_screen(end)
    return drive.plan(
        [{"command": "drag", "from": f"{a[0]},{a[1]}", "to": f"{b[0]},{b[1]}", "why": why}], profile="visible",
    )


def centre(frame: dict) -> tuple[float, float]:
    return frame["x"] + frame["width"] / 2, frame["y"] + frame["height"] / 2


# MARK: - C: filters


@scenario("C28", "Show Only Unread keeps the unread rows and the current one", fresh=True)
def show_only_unread(check):
    open_pages()
    current = islands()["currentTabID"]
    for row in rows():
        if row["tabID"] != current:
            drive.ctl("tab", "mark-read", row["tabID"])
    drive.ctl("islands", "filter", "unread")
    latch()
    state = islands()
    check.expect(state.get("filter") == "unread", f"filter is {state.get('filter')}")
    shown = [r["tabID"] for r in rows()]
    check.expect(current in shown, "the current tab's row is hidden by the filter")
    drive.screenshot("filtered")


@scenario("C29", "Show All in the filter capsule clears the filter")
def show_all(check):
    drive.ctl("islands", "filter", "unread")
    latch()
    reply = press("Show All", "clear the islands' filter")
    check.expect(reply.get("verdict") == "confirmed", f"Show All press: {reply.get('summary') or reply.get('error')}")
    drive.until(lambda: islands().get("filter") is None, message="filter cleared")
    drive.screenshot("after-show-all")


# MARK: - D: keyboard


@scenario("D43", "Latched arrows choose rows without changing the page", needs_cursor=True, fresh=True)
def arrows_choose(check):
    if not cursor_allowed(check):
        return
    open_pages()
    current = islands()["currentTabID"]
    latch()
    keys("down", "down")
    state = islands()
    check.expect(state.get("keyboardTabID") is not None, "no row chosen after two ↓")
    check.expect(state["currentTabID"] == current, "the page changed on an arrow")
    drive.screenshot("chosen")


@scenario("D46", "Typing a title after an arrow chooses that row", needs_cursor=True)
def type_select(check):
    if not cursor_allowed(check):
        return
    latch()
    keys("down", "text:webk")
    target = row_titled("WebKit")["tabID"]
    check.expect(islands().get("keyboardTabID") == target, "typing 'webk' did not choose the WebKit row")


@scenario("D47", "Space previews the chosen row", needs_cursor=True)
def space_previews(check):
    if not cursor_allowed(check):
        return
    latch()
    keys("down", "space")
    drive.screenshot("preview")
    check.note("preview: see screenshot")


@scenario("D48", "Return opens the chosen row and puts the islands away", needs_cursor=True)
def return_opens(check):
    if not cursor_allowed(check):
        return
    latch()
    keys("down", "text:webk", "return")
    time.sleep(0.8)
    state = islands()
    check.expect(state["currentTabID"] == row_titled("WebKit")["tabID"], "Return did not open the WebKit row")
    check.expect(not state["isRevealed"], "the islands stayed up after Return")


@scenario("D49", "Delete closes the chosen row and moves to the next", needs_cursor=True)
def delete_closes(check):
    if not cursor_allowed(check):
        return
    latch()
    before = len(rows())
    keys("down", "delete")
    time.sleep(0.8)
    check.expect(len(rows()) == before - 1, f"rows {before} → {len(rows())}")


@scenario("D50", "Typing in a web form with the islands latched reaches the page", needs_cursor=True, fresh=True)
def form_keys_reach_page(check):
    if not cursor_allowed(check):
        return
    open_pages(PAGES[:3] + [FORM])
    before = len(rows())
    drive.page_exec("document.getElementById('q').focus(); 'ok'")
    latch()
    keys("text:hello", "delete", "space", "return")
    time.sleep(0.8)
    value = drive.page_exec("document.getElementById('q').value")
    check.expect(len(rows()) == before, f"a tab closed while typing ({before} → {len(rows())})")
    check.expect(value.strip('"') == "hell ", f"the field holds {value!r}")


# MARK: - B: drops (real cursor)


@scenario("B14", "A link dragged from the page onto an island opens there", needs_cursor=True, fresh=True)
def link_drop(check):
    if not cursor_allowed(check):
        return
    open_pages(PAGES[:2])
    latch()
    link = drive.page_exec(
        "JSON.stringify((()=>{const a=document.querySelector('#bodyContent a[href^=\"/wiki/\"]');"
        "const r=a.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,href:a.href}})())"
    )
    import json
    link = json.loads(link.strip('"').replace('\\"', '"')) if link.startswith('"') else json.loads(link)
    target = rows()[0]
    before = len(rows())
    drag((link["x"], link["y"]), (target["x"] + 20, target["y"] + target["height"]), "drag a link onto an island")
    drive.until(lambda: len(rows()) == before + 1, message="a new row from the dropped link")
    drive.screenshot("dropped")


# MARK: - F/H: Shields and Chromium


@scenario("F80", "YouTube shows no ads with Shields on (WebKit)", fresh=True)
def youtube_webkit(check):
    drive.ctl("open", YOUTUBE)
    time.sleep(12)
    probe = drive.page_exec(AD_PROBE)
    check.expect('"ads":0' in probe and '"showing":false' in probe, f"WebKit YouTube: {probe}")


@scenario("H111", "YouTube shows no ads with Shields on (Chromium)")
def youtube_chromium(check):
    drive.ctl("tab", "engine", "chromium", timeout=90)
    time.sleep(12)
    probe = drive.page_exec(AD_PROBE)
    check.expect('"ads":0' in probe and '"showing":false' in probe, f"Chromium YouTube: {probe}")
    log = drive.ctl("page", "requests", "--blocked")
    check.expect("BLOCKED" in log, "Chromium logged no blocked request on YouTube")


@scenario("H114", "Find in page on a Chromium page counts matches")
def chromium_find(check):
    drive.ctl("navigate", "https://en.wikipedia.org/wiki/WebKit")
    time.sleep(5)
    drive.plan([
        {"command": "shortcut", "keys": "cmd+f", "why": "open find in page"},
        {"command": "type", "text": "WebKit", "why": "search the page"},
    ])
    time.sleep(1.5)
    drive.screenshot("find")
    found = drive.roc("find", "--pid", str(drive.pid()), "--label", " of ")
    check.expect(bool(found.get("matches")), "no match count shown in the find bar")
