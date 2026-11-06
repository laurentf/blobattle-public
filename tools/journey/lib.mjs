import fs from 'node:fs';
import { decode } from './png.mjs';

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export async function connect(port = 9333) {
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((resolve) => ws.addEventListener('open', resolve, { once: true }));
  let id = 0;
  const pending = new Map();
  const logs = [];
  const listeners = [];
  ws.addEventListener('message', (event) => {
    const m = JSON.parse(event.data);
    for (const listener of listeners) listener(m);
    if (m.id && pending.has(m.id)) {
      const { resolve, reject } = pending.get(m.id);
      pending.delete(m.id);
      if (m.error) reject(new Error(JSON.stringify(m.error)));
      else resolve(m.result);
      return;
    }
    if (m.method === 'Runtime.exceptionThrown') {
      logs.push(`exception: ${m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text}`);
    } else if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params.type)) {
      logs.push(`console.${m.params.type}: ${m.params.args.map((a) => a.value ?? a.description ?? '').join(' ')}`);
    }
  });
  const send = (method, params = {}, sessionId) =>
    new Promise((resolve, reject) => {
      id += 1;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params, sessionId }));
    });
  return { ws, send, logs, listeners };
}

export async function newContext(browser) {
  const { browserContextId } = await browser.send('Target.createBrowserContext', { disposeOnDetach: false });
  return browserContextId;
}

export async function openPage(browser, { url, width = 844, height = 390, scale = 3, cpu = 1, touch = true, context, init }) {
  const { targetId } = await browser.send('Target.createTarget', { url: 'about:blank', browserContextId: context });
  const { sessionId } = await browser.send('Target.attachToTarget', { targetId, flatten: true });
  const s = (method, params) => browser.send(method, params, sessionId);
  await s('Runtime.enable');
  await s('Page.enable');
  if (init) await s('Page.addScriptToEvaluateOnNewDocument', { source: init });
  const answers = [];
  const dialogs = [];
  browser.listeners.push((m) => {
    if (m.sessionId === sessionId && m.method === 'Page.javascriptDialogOpening') {
      dialogs.push(m.params.message);
      s('Page.handleJavaScriptDialog', { accept: answers.length > 0, promptText: answers.shift() ?? '' });
    }
  });
  const page = {
    s,
    dialogs,
    answer(text) {
      answers.push(text);
    },
    async resize(w, h) {
      await s('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: scale, mobile: touch });
    },
    async mouse(type, x, y, button = 'left') {
      await s('Input.dispatchMouseEvent', { type, x, y, button, buttons: type === 'mouseReleased' ? 0 : button === 'left' ? 1 : 2, clickCount: 1 });
    },
    async wheel(x, y, deltaY) {
      await s('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX: 0, deltaY });
    },
    async key(type, key, code, keyCode) {
      const text = type === 'keyDown' && key.length === 1 ? key : undefined;
      await s('Input.dispatchKeyEvent', { type, key, code, text, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode });
    },
    async eval(expression) {
      const r = await s('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      return r.result.value;
    },
    async state() {
      return page.eval('window.blobattle || null');
    },
    async waitFor(predicate, timeout = 60000, every = 250) {
      const until = Date.now() + timeout;
      let last = null;
      while (Date.now() < until) {
        last = await page.state();
        if (last && predicate(last)) return last;
        await sleep(every);
      }
      return null;
    },
    async touch(type, points) {
      await s('Input.dispatchTouchEvent', { type, touchPoints: points.map(([x, y], i) => ({ x, y, id: i + 1 })) });
    },
    async target(screen, name) {
      const s = await page.state();
      const p = s?.targets?.[screen]?.[name];
      if (!p) return null;
      const ratio = await page.eval('window.devicePixelRatio');
      const height = await page.eval("document.querySelector('canvas').height");
      return [p.x / ratio, (height - p.y) / ratio];
    },
    async press(screen, name) {
      const at = await page.target(screen, name);
      if (!at) return false;
      await page.tap(at[0], at[1]);
      return true;
    },
    async type(screen, name, text, { enter = true } = {}) {
      const at = await page.target(screen, name);
      if (!at) return false;
      await page.tap(at[0], at[1]);
      await sleep(150);
      await page.eval("document.activeElement && document.activeElement.select && document.activeElement.select(), 1");
      await s('Input.insertText', { text });
      await sleep(50);
      if (!enter) return true;
      await page.key('keyDown', 'Enter', 'Enter', 13);
      await sleep(50);
      await page.key('keyUp', 'Enter', 'Enter', 13);
      await sleep(250);
      return true;
    },
    async tap(x, y) {
      if (!touch) {
        await page.mouse('mouseMoved', x, y);
        await sleep(30);
        await page.mouse('mousePressed', x, y);
        await sleep(60);
        await page.mouse('mouseReleased', x, y);
        await sleep(120);
        return;
      }
      await page.touch('touchStart', [[x, y]]);
      await sleep(60);
      await page.touch('touchEnd', []);
      await sleep(120);
    },
    async drag(from, to, steps = 12, stepMs = 30) {
      await page.touch('touchStart', [from]);
      for (let i = 1; i <= steps; i += 1) {
        await sleep(stepMs);
        await page.touch('touchMove', [[from[0] + ((to[0] - from[0]) * i) / steps, from[1] + ((to[1] - from[1]) * i) / steps]]);
      }
      await sleep(stepMs);
      await page.touch('touchEnd', []);
    },
    async shot(file) {
      const { data } = await s('Page.captureScreenshot', { format: 'png' });
      const bytes = Buffer.from(data, 'base64');
      fs.writeFileSync(file, bytes);
      return decode(bytes);
    },
    async close() {
      await browser.send('Target.closeTarget', { targetId });
    },
  };
  await page.resize(width, height);
  await s('Emulation.setTouchEmulationEnabled', { enabled: touch, maxTouchPoints: 5 });
  if (cpu > 1) await s('Emulation.setCPUThrottlingRate', { rate: cpu });
  await s('Page.navigate', { url });
  return page;
}

export function reporter() {
  let failed = 0;
  return {
    check(title, ok, detail = '') {
      if (!ok) failed += 1;
      console.log(`${ok ? '✅' : '❌'} ${title}${detail ? ` — ${detail}` : ''}`);
      return ok;
    },
    section(title) {
      console.log(`── ${title}`);
    },
    get failed() {
      return failed;
    },
  };
}

export async function pick(page, cell) {
  await page.press('hud', 'weapon');
  await page.waitFor((s) => s.game?.grid && s.targets?.hud?.[cell], 5000);
  await page.press('hud', cell);
  return page.waitFor((s) => s.game && !s.game.grid, 5000);
}

export async function css(page, p) {
  const ratio = await page.eval('window.devicePixelRatio');
  const height = await page.eval("document.querySelector('canvas').height");
  return [p.x / ratio, (height - p.y) / ratio];
}

export async function steady(page) {
  let last = null;
  for (let i = 0; i < 40; i += 1) {
    const b = (await page.state()).game?.blob;
    if (b && last && Math.abs(b.x - last.x) < 2 && Math.abs(b.y - last.y) < 2) return true;
    last = b;
    await sleep(100);
  }
  return false;
}

export async function sling(page, dx, dy) {
  await steady(page);
  const s = await page.state();
  if (!s.game?.blob) return false;
  const from = await css(page, s.game.blob);
  await page.touch('touchStart', [from]);
  for (let i = 1; i <= 10; i += 1) {
    await sleep(30);
    await page.touch('touchMove', [[from[0] + (dx * i) / 10, from[1] + (dy * i) / 10]]);
  }
  await sleep(120);
  await page.touch('touchEnd', []);
  return true;
}
