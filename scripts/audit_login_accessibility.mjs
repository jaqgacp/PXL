// PXL-AUD-060 login accessibility regression.
//
// Proves the login form is reachable by accessible label (not CSS selectors)
// and carries the expected autocomplete/name/error semantics. It serves the
// locally built app and NEVER submits credentials, so it makes no hosted call.
//
// Usage: node scripts/audit_login_accessibility.mjs
// Prerequisite: `npm run build` (this script serves dist via `vite preview`).

import { spawn } from 'node:child_process';
import { chromium } from 'playwright';

const PORT = Number(process.env.LOGIN_A11Y_PORT || 41739);
const BASE_URL = `http://localhost:${PORT}`;

function assert(condition, message) {
  if (!condition) throw new Error(`Assertion failed: ${message}`);
  console.log(`  ok - ${message}`);
}

async function waitForServer(url, timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {
      // server not ready yet
    }
    await new Promise(r => setTimeout(r, 300));
  }
  throw new Error(`Preview server did not become ready at ${url} within ${timeoutMs}ms`);
}

const server = spawn('npx', ['vite', 'preview', '--port', String(PORT), '--strictPort'], {
  stdio: ['ignore', 'ignore', 'inherit'],
});

let browser;
let exitCode = 0;
try {
  await waitForServer(BASE_URL);
  browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });

  const emailField = page.getByLabel('Email');
  const passwordField = page.getByLabel('Password');

  await emailField.waitFor({ state: 'visible', timeout: 15000 });
  console.log('Login accessibility checks:');

  // Label-based resolution (the defect: previously required input[type=...] CSS).
  assert((await emailField.count()) === 1, 'getByLabel("Email") resolves exactly one input');
  assert((await passwordField.count()) === 1, 'getByLabel("Password") resolves exactly one input');

  // Fields are fillable by label (automation reliability). No submit occurs.
  await emailField.fill('probe@example.com');
  await passwordField.fill('probe-secret');
  assert((await emailField.inputValue()) === 'probe@example.com', 'email input fillable by label');
  assert((await passwordField.inputValue()) === 'probe-secret', 'password input fillable by label');

  // Autocomplete + name semantics.
  assert((await emailField.getAttribute('name')) === 'email', 'email input has name="email"');
  assert((await emailField.getAttribute('autocomplete')) === 'email', 'email input has autocomplete="email"');
  assert((await passwordField.getAttribute('name')) === 'password', 'password input has name="password"');
  assert((await passwordField.getAttribute('autocomplete')) === 'current-password', 'password input has autocomplete="current-password"');

  // Accessible error region exists as a live region for login failures.
  const alertRegion = page.getByRole('alert');
  assert((await alertRegion.count()) === 1, 'accessible error region with role="alert" is present');
  assert((await alertRegion.getAttribute('aria-live')) === 'assertive', 'error region is an assertive live region');

  console.log('\nPXL-AUD-060 login accessibility audit passed.');
} catch (err) {
  exitCode = 1;
  console.error(`\nPXL-AUD-060 login accessibility audit FAILED: ${err.message}`);
} finally {
  if (browser) await browser.close();
  server.kill('SIGTERM');
}

process.exit(exitCode);
