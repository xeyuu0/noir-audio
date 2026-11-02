// Browser acceptance checks for the complete multipage site and real release files.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL, fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
if (!process.env.PLAYWRIGHT_MODULE) throw new Error('Set PLAYWRIGHT_MODULE to an installed playwright-core directory.');
const { chromium } = await import(pathToFileURL(path.join(process.env.PLAYWRIGHT_MODULE, 'index.mjs')));
const base = process.env.SITE_URL || 'http://127.0.0.1:4173';
const visualOnly = process.env.VISUAL_ONLY === '1';
const output = path.join(root, 'test-results');
await fs.mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: process.env.BROWSER_EXECUTABLE || undefined });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1, acceptDownloads: true });
await context.addInitScript(() => {
  window.__viewTransitionSeen = false;
  addEventListener('pagereveal', event => { window.__viewTransitionSeen = Boolean(event.viewTransition); });
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
let checks = 0;
function check(value, label) { if (!value) throw new Error(`FAIL ${label}`); checks++; console.log(`PASS ${label}`); }
const fits = () => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
const settle = () => page.waitForFunction(() => document.getAnimations().every(animation => animation.playState !== 'running'));
async function capture(name) {
  await settle();
  await page.mouse.move(0, 0);
  await page.evaluate(async () => {
    for (let y = 0; y < document.body.scrollHeight; y += innerHeight * .7) {
      scrollTo({ top: y, behavior: 'instant' });
      await new Promise(resolve => setTimeout(resolve, 120));
    }
    scrollTo({ top: 0, behavior: 'instant' });
  });
  await settle();
  check(await page.locator('.reveal-pending').evaluateAll(items => items.every(item => item.classList.contains('is-visible'))), `Scroll reveals all content: ${name}`);
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.screenshot({ path: path.join(output, `${name}-hero.png`) });
  await page.screenshot({ path: path.join(output, `${name}.png`), fullPage: true });
}
const routes = ['/', '/studio', '/effects', '/routing', '/download', '/install', '/release', '/windows'];
try {
  check((await page.goto(base)).ok(), 'Homepage responds successfully');
  await settle();
  check(await page.locator('.sculpture').evaluate(img => img.complete && img.naturalWidth > 0), 'Original waveform sculpture loads');
  await page.keyboard.press('Tab');
  check(await page.locator('.skip-link').evaluate(link => link === document.activeElement), 'First keyboard target is the skip link');
  await page.keyboard.press('Enter');
  check(await page.locator('main').evaluate(main => main === document.activeElement), 'Skip link moves focus to main content');
  await page.evaluate(() => scrollTo({ top: 0, behavior: 'instant' }));
  const glass = await page.locator('.site-header').evaluate(el => getComputedStyle(el).backdropFilter);
  check(glass.includes('blur'), 'Floating glass navigation uses backdrop blur');
  await page.locator('.hero-art').hover({ position: { x: 80, y: 80 } });
  await page.waitForFunction(() => document.querySelector('.hero-art').style.getPropertyValue('--pointer-x'));
  check(await page.locator('.hero-art').evaluate(el => el.style.getPropertyValue('--pointer-x') !== ''), 'Sculpture responds to a fine pointer');
  await page.mouse.move(10, 10);
  await capture('desktop');

  await page.locator('#site-nav a[href="/studio"]').click();
  await page.waitForURL(base + '/studio');
  await settle();
  check(await page.evaluate(() => window.__viewTransitionSeen), 'Navigation triggers a real cross-document view transition');
  check(await page.locator('#site-nav a[href="/studio"]').getAttribute('aria-current') === 'page', 'Current page is identified in navigation');
  await page.goBack();
  await page.waitForURL(url => url.pathname === '/');
  check(await page.locator('h1').innerText().then(text => text.includes('Sound.')), 'Browser Back returns to the homepage');

  const internal = new Set();
  const titles = new Set();
  for (const route of routes) {
    check((await page.goto(base + route)).ok(), `Page resolves: ${route}`);
    const title = await page.title();
    check(!titles.has(title), `Unique page title: ${route}`); titles.add(title);
    check(await page.locator('h1').count() === 1, `One primary heading: ${route}`);
    check(await page.locator('html').getAttribute('lang') === 'en', `Document language declared: ${route}`);
    check(await page.locator('link[rel="canonical"]').getAttribute('href') === 'https://noir-audio-orpin.vercel.app' + route, `Canonical route: ${route}`);
    check(await page.evaluate(() => { const ids = [...document.querySelectorAll('[id]')].map(el => el.id); return ids.length === new Set(ids).size; }), `No duplicate IDs: ${route}`);
    (await page.locator('a[href]').evaluateAll(links => links.map(link => link.getAttribute('href')).filter(href => href.startsWith('/')))).forEach(href => internal.add(href));
    for (const width of [320, 375, 768, 1024, 1440, 1920]) {
      await page.setViewportSize({ width, height: 900 });
      check(await fits(), `No horizontal overflow: ${route} at ${width}px`);
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    if (['/studio', '/effects', '/routing', '/download'].includes(route)) await capture(route.slice(1) + '-desktop');
    await page.setViewportSize({ width: 375, height: 900 });
    await capture(route === '/' ? 'mobile' : route.slice(1) + '-mobile');
  }

  for (const route of ['/studio', '/effects', '/routing']) {
    await page.goto(base + route);
    const tabs = page.locator('[role="tab"]');
    await tabs.first().focus(); await page.keyboard.press('ArrowRight');
    check(await tabs.nth(1).getAttribute('aria-selected') === 'true', `Arrow key selects next tab: ${route}`);
    check(await page.locator('#' + await tabs.nth(1).getAttribute('aria-controls')).isVisible(), `Selected tab exposes its panel: ${route}`);
    check(await page.locator('[role="tabpanel"]:visible').count() === 1, `Only one tab panel is visible: ${route}`);
    await page.keyboard.press('End');
    check(await tabs.last().getAttribute('aria-selected') === 'true', `End selects last tab: ${route}`);
    await page.keyboard.press('ArrowRight');
    check(await tabs.first().getAttribute('aria-selected') === 'true', `Tab navigation wraps: ${route}`);
    await page.keyboard.press('ArrowLeft');
    check(await tabs.last().getAttribute('aria-selected') === 'true', `Left arrow wraps backward: ${route}`);
    await page.keyboard.press('Home');
    check(await tabs.first().getAttribute('aria-selected') === 'true', `Home selects first tab: ${route}`);
    await tabs.last().click();
    check(await tabs.last().getAttribute('aria-selected') === 'true', `Pointer selection works: ${route}`);
    check(await fits(), `Alternate panel fits mobile: ${route}`);
    if (route === '/studio') check(await page.locator('[role="tabpanel"]:visible img').evaluate(img => img.complete && img.naturalWidth === 1300), 'Actual dashboard screenshot loads');
  }

  await page.goto(base + '/download');
  const summary = page.locator('summary').first();
  await summary.focus(); await page.keyboard.press('Enter');
  check(await page.locator('details').first().getAttribute('open') !== null, 'FAQ expands with keyboard');
  await page.keyboard.press('Enter');
  check(await page.locator('details').first().getAttribute('open') === null, 'FAQ collapses with keyboard');
  await page.locator('.menu-toggle').click();
  check(await page.locator('.menu-toggle').getAttribute('aria-expanded') === 'true', 'Mobile navigation opens');
  check(await page.locator('#site-nav').isVisible(), 'Mobile navigation links are visible');
  await page.keyboard.press('Tab');
  check(await page.locator('#site-nav a').first().evaluate(el => document.activeElement === el), 'Mobile menu is reachable by keyboard');
  await page.keyboard.press('Escape');
  check(await page.locator('.menu-toggle').getAttribute('aria-expanded') === 'false', 'Escape closes mobile navigation');
  check(await page.locator('.menu-toggle').evaluate(el => document.activeElement === el), 'Escape restores menu button focus');
  await page.locator('.menu-toggle').click();
  await page.locator('#site-nav a[href="/routing"]').click();
  await page.waitForURL(base + '/routing');
  check(await page.locator('.menu-toggle').getAttribute('aria-expanded') === 'false', 'Following a mobile link closes navigation');
  await page.locator('.menu-toggle').click();
  await page.mouse.click(5, 650);
  check(await page.locator('.menu-toggle').getAttribute('aria-expanded') === 'false', 'Clicking outside closes mobile navigation');
  await page.locator('.menu-toggle').click();
  await page.setViewportSize({ width: 1440, height: 900 });
  check(await page.locator('#site-nav').isVisible(), 'Desktop navigation remains visible after a resize');
  await page.setViewportSize({ width: 375, height: 900 });
  await page.locator('#site-nav').waitFor({ state: 'hidden' });
  check(!await page.locator('#site-nav').isVisible(), 'Mobile menu returns to closed after a resize');

  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto(base);
  check(await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior === 'auto'), 'Reduced motion disables smooth scrolling');
  check(await page.evaluate(() => document.getAnimations().filter(animation => animation.playState === 'running').length === 0), 'Reduced motion disables introduction animations');
  check(await page.locator('.reveal').evaluateAll(items => items.every(item => getComputedStyle(item).opacity === '1')), 'All reveal content is visible with reduced motion');
  await page.locator('.hero-art').hover({ position: { x: 80, y: 80 } });
  check(await page.locator('.hero-art').evaluate(el => !el.style.getPropertyValue('--pointer-x')), 'Reduced motion disables pointer parallax');
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.locator('#site-nav a[href="/studio"]').click();
  await page.waitForURL(base + '/studio');
  check(!await page.evaluate(() => window.__viewTransitionSeen), 'Reduced motion disables document transitions');
  await page.setViewportSize({ width: 812, height: 375 });
  check(await fits(), 'Landscape layout fits the viewport');

  for (const href of internal) {
    if (visualOnly && href.startsWith('/downloads/')) continue;
    const target = new URL(href, base);
    const response = await context.request.get(target.href);
    check(response.ok(), `Internal link resolves: ${href}`);
    if (target.hash) {
      await page.goto(target.href);
      check(await page.locator(target.hash).count() === 1, `Linked anchor exists: ${href}`);
    }
  }
  const sitemap = await context.request.get(base + '/sitemap.xml');
  const xml = await sitemap.text();
  check(routes.every(route => xml.includes('https://noir-audio-orpin.vercel.app' + route + '</loc>')), 'Sitemap includes all eight public pages');

  const noJS = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 375, height: 900 } });
  const fallback = await noJS.newPage();
  await fallback.goto(base);
  check(await fallback.locator('#site-nav a[href="/download"]').isVisible(), 'Navigation is usable without JavaScript');
  check(await fallback.locator('.reveal').evaluateAll(items => items.every(item => getComputedStyle(item).opacity === '1')), 'Content is visible without JavaScript');
  await fallback.locator('#site-nav a[href="/download"]').click();
  check(fallback.url() === base + '/download', 'Native links navigate without JavaScript');
  check(await fallback.locator('.download-app').isVisible(), 'Download remains accessible without JavaScript');
  await noJS.close();

  if (!visualOnly) {
    const checksums = await (await context.request.get(base + '/downloads/SHA256SUMS.txt')).text();
    for (const line of checksums.trim().split('\n')) {
      const [, expected, filename] = line.match(/^([a-f0-9]{64})\s+(.+)$/) || [];
      check(Boolean(filename), 'Checksum entry has SHA-256 digest and filename');
      const response = await context.request.get(base + '/downloads/' + encodeURIComponent(filename));
      check(response.ok(), `Artifact is downloadable: ${filename}`);
      const data = await response.body();
      check(crypto.createHash('sha256').update(data).digest('hex') === expected, `Downloaded bytes match SHA-256: ${filename}`);
      check(data.equals(await fs.readFile(path.join(root, 'public/downloads', filename))), `Hosted artifact matches local release: ${filename}`);
    }
    await page.goto(base + '/download');
    const received = page.waitForEvent('download');
    await page.locator('.download-app').click();
    const download = await received;
    check(download.suggestedFilename() === 'NOIR-Audio-0.1.0-macOS-arm64.dmg', 'Mac button starts the real disk image download');
    check(await download.failure() === null, 'Browser download finishes successfully');
    const windowsReceived = page.waitForEvent('download');
    await page.locator('.download-windows').click();
    const windowsDownload = await windowsReceived;
    check(windowsDownload.suggestedFilename() === 'NOIR-Audio-0.1.0-Windows-x64-Setup.exe', 'Windows button downloads the actual setup installer');
    check(await windowsDownload.failure() === null, 'Windows setup download completes');
    check(await page.locator('footer a[href="https://github.com/xeyuu0/noir-audio"]').count() === 1, 'Footer links to the published source repository');
  }
  check(errors.length === 0, `No browser JavaScript or console errors (${errors.join('; ')})`);
  console.log(`RESULT ${checks} website checks passed against ${base}`);
} finally { await browser.close(); }
