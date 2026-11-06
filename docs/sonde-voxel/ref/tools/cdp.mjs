import fs from 'node:fs';

const args = Object.fromEntries(process.argv.slice(2).map(a => { const i = a.indexOf('='); return [a.slice(0, i), a.slice(i + 1)]; }));
const url = args.url;
const rate = Number(args.rate || 1);
const waitExpr = args.wait || 'false';
const timeoutMs = Number(args.timeout || 120000);
const shot = args.shot;
const out = args.out;
const width = Number(args.w || 844), height = Number(args.h || 390);
const dsf = Number(args.dsf || 3);
const taps = args.taps ? JSON.parse(args.taps) : [];

const ver = await (await fetch('http://localhost:9333/json/version')).json();
const ws = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let id = 0;
const pending = new Map();
const logs = [];
ws.addEventListener('message', ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { const { res, rej } = pending.get(m.id); pending.delete(m.id); m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result); return; }
  if (m.method === 'Runtime.consoleAPICalled') logs.push(`[console.${m.params.type}] ` + m.params.args.map(a => a.value ?? a.description ?? '').join(' '));
  else if (m.method === 'Runtime.exceptionThrown') logs.push('[exception] ' + JSON.stringify(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text));
  else if (m.method === 'Log.entryAdded') logs.push(`[log.${m.params.entry.level}] ${m.params.entry.text} ${m.params.entry.url || ''}`);
});
const send = (method, params = {}, sessionId) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });

const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
const s = (m, p) => send(m, p, sessionId);
await s('Runtime.enable'); await s('Log.enable'); await s('Page.enable');
await s('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: dsf, mobile: true });
await s('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
if (rate > 1) await s('Emulation.setCPUThrottlingRate', { rate });
const t0 = Date.now();
await s('Page.navigate', { url });
const evalv = async (expression) => (await s('Runtime.evaluate', { expression, returnByValue: true })).result.value;
let done = false;
while (Date.now() - t0 < timeoutMs) {
  await new Promise(r => setTimeout(r, 500));
  try { if (await evalv(waitExpr)) { done = true; break; } } catch (e) { }
}
for (const t of taps) {
  await s('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: t[0], y: t[1] }] });
  await s('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await new Promise(r => setTimeout(r, 400));
  await s('Input.dispatchMouseEvent', { type: 'mousePressed', x: t[0], y: t[1], button: 'left', clickCount: 1 });
  await s('Input.dispatchMouseEvent', { type: 'mouseReleased', x: t[0], y: t[1], button: 'left', clickCount: 1 });
  await new Promise(r => setTimeout(r, 600));
}
const result = {
  done, elapsed_ms: Date.now() - t0,
  proto: await evalv('window.proto || null'),
  phases: await evalv('window.phases || null'),
  webgl: await evalv("(function(){var c=document.querySelector('canvas'); if(!c) return null; var g=c.getContext('webgl2')||c.getContext('webgl'); if(!g) return 'no ctx'; var e=g.getExtension('WEBGL_debug_renderer_info'); return [c.width,c.height,g.getParameter(g.VERSION), e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):'', g.getParameter(g.MAX_TEXTURE_SIZE)].join(' | ');})()"),
  logs,
};
if (shot) { const { data } = await s('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(shot, Buffer.from(data, 'base64')); }
const txt = JSON.stringify(result, null, 1);
if (out) fs.writeFileSync(out, txt);
console.log(txt.length > 20000 ? txt.slice(0, 20000) + '...' : txt);
await send('Target.closeTarget', { targetId });
ws.close();
process.exit(0);
