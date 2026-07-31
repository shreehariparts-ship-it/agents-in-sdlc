---
description: Full automatic browser test of a UI — every button, formulas, desktop + mobile, console errors, pass/fail + screenshots
---

Run a complete browser test of the target UI and report results. The target is
the argument if given (a URL or file path), otherwise the UI just built/changed
in this session: $ARGUMENTS

Do ALL of the following automatically — do not ask for permission between steps:

1. **Serve / open the target.**
   - Local project → build and serve it on `http://localhost:<port>` (give the
     server a readiness check, not a fixed sleep).
   - A URL → use it directly. If it is a remote/public host and navigation fails
     with a proxy `403`, STOP and tell the user the environment's network policy
     must allow that domain (Full, or Custom with the domain listed) — do not
     pretend the test ran.

2. **Discover every interactive element** on the page: buttons, links that act,
   toggles, tabs, dropdowns/selects, inputs, draggable handles, canvas controls.

3. **Test each one — aim for 100% coverage.** Click/tap it, or fill it, and after
   each interaction **assert the result**:
   - Counters/totals/computed rates/derived fields show the correct value.
   - The right panel/section/state appears.
   - Prefer keyboard (Tab/Enter/shortcuts) when mouse handling is unreliable.
   A control that reacts but produces the wrong value is a **FAIL**, not a pass.

4. **Run the whole pass in two viewports:** a desktop viewport and a mobile
   device emulation (e.g. iPhone 13 and/or Pixel 7). Report both.

5. **Capture JS console errors** during the run; list any that appear.

6. **Take screenshots** — at minimum before/after key interactions, and one per
   viewport — and send them to the user.

7. **Report** a per-element table: element → ✅ pass / ❌ fail → note. For every
   ❌, say exactly what happened (wrong value, nothing appeared, console error,
   element not found). End with an overall pass count `N/total`.

Engines you can use: `scripts/speed-browser/speed-browser.mjs` (fast, parallel,
warm browser — best for a defined suite; pass a `tasks.json`), or the Playwright
MCP browser tools directly for exploration. Use the bundled Chromium; serve local
content over `http://localhost` (the MCP browser blocks `file://`).
