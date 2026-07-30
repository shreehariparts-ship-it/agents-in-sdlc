// Multi-task speed-testing browser harness.
//
// ONE warm headless Chromium -> many tasks run in PARALLEL -> per-task timing,
// assertions, and screenshots. Uses the same bundled Chromium the Playwright
// MCP server is configured for in .mcp.json.
//
// Usage:
//   node scripts/speed-browser/speed-browser.mjs [tasks.json]
//     - No arg: runs the built-in demo task set (demo.html + form.html here).
//     - tasks.json: an array of task objects (see example-tasks.json).
//
// Task shape:
//   {
//     "name": "login@mobile",
//     "url": "http://localhost:3000/",   // http(s):// or file://
//     "device": "iPhone 13",             // optional Playwright device to emulate
//     "viewport": { "width": 900, "height": 600 },  // used if no device
//     "actions": [ {"type":["#email","a@b.com"]}, {"click":"#login"} ],
//     "expect": { "selector": "#welcome", "equals": "Welcome!" }  // optional assertion
//   }
//
// Supported actions: {"click":"#sel"} | {"type":["#sel","text"]}
//                    | {"waitFor":"#sel"} | {"wait": ms}

import { createRequire } from 'node:module';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));

// Resolve playwright-core from a normal install or an npx cache (@playwright/mcp).
function loadPlaywright() {
  for (const n of ['playwright-core', 'playwright']) {
    try { return require(n); } catch { /* next */ }
  }
  const root = join(process.env.HOME || '/root', '.npm', '_npx');
  if (existsSync(root)) {
    for (const d of readdirSync(root)) {
      const p = join(root, d, 'node_modules', 'playwright-core');
      if (existsSync(p)) return require(p);
    }
  }
  throw new Error('playwright-core not found — run `npm i -D playwright-core`.');
}
const { chromium, devices } = loadPlaywright();

// Built-in demo tasks (fixtures live next to this script).
const F = (name) => 'file://' + join(HERE, name);
const defaultTasks = [
  { name: 'button@desktop', url: F('demo.html'), viewport: { width: 900, height: 600 },
    actions: [{ click: '#btn' }, { click: '#btn' }, { click: '#btn' }], expect: { selector: '#count', equals: '3' } },
  { name: 'button@mobile', url: F('demo.html'), device: 'iPhone 13',
    actions: [{ click: '#btn' }, { click: '#btn' }, { click: '#btn' }], expect: { selector: '#count', equals: '3' } },
  { name: 'form@desktop', url: F('form.html'), viewport: { width: 900, height: 600 },
    actions: [{ type: ['#name', 'Raju'] }, { click: '#go' }], expect: { selector: '#out', equals: '👋 Hello, Raju!' } },
  { name: 'form@mobile', url: F('form.html'), device: 'Pixel 7',
    actions: [{ type: ['#name', 'Mobile'] }, { click: '#go' }], expect: { selector: '#out', equals: '👋 Hello, Mobile!' } },
];

const tasks = process.argv[2] ? JSON.parse(readFileSync(process.argv[2], 'utf8')) : defaultTasks;
const execPath = join(process.env.PLAYWRIGHT_BROWSERS_PATH || '', 'chromium');
const now = () => Number(process.hrtime.bigint() / 1000000n);

const launchStart = now();
const browser = await chromium.launch({
  executablePath: existsSync(execPath) ? execPath : undefined,
  headless: true,
  args: ['--no-sandbox'],
});
const launchMs = now() - launchStart;

async function runTask(t) {
  const start = now();
  const ctx = await browser.newContext(
    t.device ? { ...devices[t.device] } : { viewport: t.viewport || { width: 1280, height: 800 } }
  );
  const page = await ctx.newPage();
  try {
    const resp = await page.goto(t.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const status = resp ? resp.status() : 0;
    for (const a of (t.actions || [])) {
      if (a.click) await page.click(a.click);
      else if (a.type) await page.fill(a.type[0], a.type[1]);
      else if (a.waitFor) await page.waitForSelector(a.waitFor);
      else if (a.wait) await page.waitForTimeout(a.wait);
    }
    let ok = true, got = null;
    if (t.expect) { got = (await page.textContent(t.expect.selector))?.trim(); ok = got === t.expect.equals; }
    const shot = join(HERE, 'speed-' + t.name.replace(/[^a-z0-9]+/gi, '_') + '.png');
    await page.screenshot({ path: shot });
    await ctx.close();
    return { name: t.name, status, ok, got, ms: now() - start, shot };
  } catch (e) {
    await ctx.close().catch(() => {});
    return { name: t.name, status: 0, ok: false, err: e.message.split('\n')[0], ms: now() - start };
  }
}

const wallStart = now();
const results = await Promise.all(tasks.map(runTask));
const wallMs = now() - wallStart;
await browser.close();

console.log(`Chromium ${browser.version?.() ?? ''} | launch: ${launchMs}ms | tasks: ${tasks.length}`);
console.log('─'.repeat(72));
console.log('TASK'.padEnd(18), 'RESULT'.padEnd(8), 'HTTP'.padEnd(6), 'TIME'.padEnd(8), 'DETAIL');
for (const r of results) {
  const res = r.err ? 'ERROR' : (r.ok ? 'PASS' : 'FAIL');
  const detail = r.err ? r.err : (r.got != null ? `got="${r.got}"` : '');
  console.log(String(r.name).padEnd(18), res.padEnd(8), String(r.status).padEnd(6), `${r.ms}ms`.padEnd(8), detail);
}
console.log('─'.repeat(72));
const sum = results.reduce((a, r) => a + r.ms, 0);
const slow = Math.max(...results.map((r) => r.ms));
console.log(`PARALLEL wall-clock: ${wallMs}ms  (slowest task ${slow}ms; sequential would be ~${sum}ms)`);
const passed = results.filter((r) => r.ok).length;
console.log(`Passed: ${passed}/${results.length}`);

process.exit(passed === results.length ? 0 : 1);
