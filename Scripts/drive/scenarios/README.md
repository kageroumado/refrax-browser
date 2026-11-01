Scenario modules for `drive.py`. Each file registers scenarios with `@drive.scenario("B14", "title")`;
a scenario takes a `Check`, sets up through `drive.ctl`, acts through one `drive.plan([...])`, and
records failures with `check.expect(...)` and evidence with `drive.screenshot(...)`.
