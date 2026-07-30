# Speed Browser — multi-task parallel browser tester

A small harness that drives the environment's bundled Chromium (the same one
the Playwright MCP server uses, per the repo's `.mcp.json`) to test many pages
at once. It launches **one warm browser** and runs every task in **parallel**,
each in its own browser context, then reports per-task timing, assertions, and
screenshots.

## Why

- **Fast:** one browser launch is shared by all tasks; tasks run concurrently,
  so wall-clock ≈ the slowest single task rather than the sum of all tasks.
- **Multi-task:** test several pages / buttons / forms in a single run.
- **Desktop + mobile:** each task can emulate a mobile device (viewport, touch,
  user-agent) or use a custom viewport.

## Run

```bash
# Built-in demo task set (demo.html + form.html in this folder):
node scripts/speed-browser/speed-browser.mjs

# Your own tasks:
node scripts/speed-browser/speed-browser.mjs path/to/tasks.json
```

Exit code is `0` when all tasks pass, `1` otherwise — usable in CI.

## Task format

`tasks.json` is an array of task objects:

```json
[
  {
    "name": "login@mobile",
    "url": "http://localhost:3000/",
    "device": "iPhone 13",
    "viewport": { "width": 900, "height": 600 },
    "actions": [
      { "type": ["#email", "a@b.com"] },
      { "type": ["#pass", "secret"] },
      { "click": "#login" }
    ],
    "expect": { "selector": "#welcome", "equals": "Welcome!" }
  }
]
```

| Field      | Required | Notes                                                        |
|------------|----------|-------------------------------------------------------------|
| `name`     | yes      | Label + screenshot filename                                 |
| `url`      | yes      | `http(s)://` or `file://` (local HTML)                       |
| `device`   | no       | Playwright device name to emulate, e.g. `"iPhone 13"`       |
| `viewport` | no       | Used when `device` is absent (default `1280×800`)           |
| `actions`  | no       | Ordered steps (see below)                                   |
| `expect`   | no       | Assert an element's trimmed text equals a value             |

**Actions:** `{"click":"#sel"}`, `{"type":["#sel","text"]}`,
`{"waitFor":"#sel"}`, `{"wait": 500}`.

See [`example-tasks.json`](./example-tasks.json) for a working sample.

## Notes

- Screenshots are written next to the script as `speed-<name>.png`.
- Live navigation to public sites may be blocked by the environment's network
  egress policy; local (`file://`, `localhost`) and allowlisted hosts work.
- Resolves `playwright-core` from a normal install or an npx cache, and finds
  Chromium via `PLAYWRIGHT_BROWSERS_PATH`.
