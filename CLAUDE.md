# Project guidance for Claude Code

This repo hosts the GitHub Copilot workshop site (`website/`, Astro + Starlight)
plus developer tooling under `scripts/`.

## Browser / UI testing policy (automatic)

**Whenever you build, deploy, generate, or modify any HTML/UI, you MUST verify it
in a real browser before you say it is done.** Do not claim a UI works from the
code alone — prove it by driving the page.

The browser is already wired up:
- Playwright MCP browser is configured in `.mcp.json` (bundled Chromium).
- A ready multi-task tester lives at `scripts/speed-browser/` (see its README).
- The `/test-ui` command runs the full routine on demand.

For every UI change, do all of this automatically (no need to be asked):

1. **Serve it.** Build and serve the page locally (localhost). Remote hosts only
   work if the environment's network policy allows them (see Network notes below).
2. **Test every interactive element — 100%.** Click every button, toggle, tab,
   and dropdown; fill every input; trigger every action. Nothing untested.
3. **Verify the logic/formulas.** After each interaction, assert the visible
   result is correct — counters, totals, computed rates, derived fields. A button
   that "clicks" but computes the wrong number is a FAIL.
4. **Desktop AND mobile.** Run each check in a desktop viewport and a mobile
   device emulation (e.g. iPhone 13 / Pixel 7). Layout and touch must both work.
5. **Capture JS console errors.** Any console error is a finding, even if the UI
   looks fine.
6. **Report pass/fail per element, with screenshots.** For each item: ✅ pass or
   ❌ fail, a screenshot, and for failures exactly what went wrong.

Prefer **keyboard interactions** (Tab/Enter/shortcuts) over mouse where a page's
mouse handling is unreliable.

Use `scripts/speed-browser/speed-browser.mjs` (one warm browser, tasks run in
parallel — fast) for repeatable suites, or drive the Playwright MCP tools
directly for exploratory checks. Screenshots go to the user.

## Network notes

- The Playwright browser navigates through the **session's own network**, so a
  remote site (e.g. a hosted app) is reachable only if the environment's network
  access is **Full** or **Custom** with that domain allowed. `localhost` /
  `file://`-served content always works. Public sites fail with a proxy `403`
  under the default **Trusted** policy.
- The MCP browser blocks `file://` by default — serve over `http://localhost`.

## Reusing this in another repo

To get the same automatic testing in a different project, copy `CLAUDE.md`,
`.claude/commands/test-ui.md`, `.mcp.json`, and `scripts/speed-browser/` into
that repo. Then every session there knows the policy and has the tools.
