// Browser smoke test for the Playwright MCP setup.
//
// Verifies that the Chromium build wired up in this environment launches and
// renders, using the same flags the Playwright MCP server is configured with
// in `.mcp.json` (`--browser chromium --headless --no-sandbox`).
//
// Usage: node scripts/browser-smoke-test.mjs [url]
//   - Always runs an offline render check (no network required).
//   - If a URL is given (or reachable), also attempts a live navigation.
//
// Notes:
//   - Set PLAYWRIGHT_BROWSERS_PATH so the bundled Chromium can be located;
//     otherwise playwright-core resolves its own download.
//   - Live navigation depends on the environment's network egress policy.

import { createRequire } from 'node:module';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const require = createRequire(import.meta.url);

// Resolve playwright-core / playwright from a normal install, or fall back to
// an npx cache (useful when it's not a repo dependency, e.g. via @playwright/mcp).
function loadPlaywright() {
  for (const name of ['playwright-core', 'playwright']) {
    try {
      return require(name);
    } catch {
      /* try next */
    }
  }
  const npxRoot = join(process.env.HOME || '/root', '.npm', '_npx');
  if (existsSync(npxRoot)) {
    for (const dir of readdirSync(npxRoot)) {
      const p = join(npxRoot, dir, 'node_modules', 'playwright-core');
      if (existsSync(p)) return require(p);
    }
  }
  throw new Error('playwright-core not found — run `npm i -D playwright-core`.');
}

const { chromium } = loadPlaywright();

// Prefer the environment's bundled Chromium if PLAYWRIGHT_BROWSERS_PATH points at one.
const browsersPath = process.env.PLAYWRIGHT_BROWSERS_PATH;
const bundled = browsersPath ? join(browsersPath, 'chromium') : null;
const executablePath = bundled && existsSync(bundled) ? bundled : undefined;

const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined;

const browser = await chromium.launch({
  executablePath,
  headless: true,
  args: ['--no-sandbox'],
  proxy,
});
console.log('LAUNCH: ok — Chromium', browser.version());

const ctx = await browser.newContext();

// 1) Offline render — proves the engine parses and renders the DOM (no network).
const p1 = await ctx.newPage();
await p1.setContent('<title>Offline Render</title><h1 id="h">Hello from Chromium</h1>');
console.log('OFFLINE title:', await p1.title());
console.log('OFFLINE h1   :', await p1.textContent('#h'));

// 2) Optional live navigation — subject to the environment's network policy.
const url = process.argv[2] || 'https://example.com';
try {
  const p2 = await ctx.newPage();
  const resp = await p2.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  console.log('NAV status  :', resp && resp.status());
  console.log('NAV title   :', await p2.title());
} catch (e) {
  console.log('NAV error   :', e.message.split('\n')[0], '(likely network-policy gated)');
}

await browser.close();
console.log('CLOSE: ok');
