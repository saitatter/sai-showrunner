import { createServer } from 'node:http';
import { existsSync, readFileSync, mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join, extname, sep } from 'node:path';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
const root = resolve(import.meta.dirname, '../..');
const dist = join(root, 'packages/showrunner-obs-overlay/dist/obs-overlay');
const candidates = [process.env.SHOWRUNNER_CHROMIUM_BINARY,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe', '/usr/bin/chromium', '/usr/bin/google-chrome'].filter(Boolean);
const browser = candidates.find(existsSync);
if (!browser) throw new Error('Set SHOWRUNNER_CHROMIUM_BINARY to a Chrome or Edge executable.');
if (!existsSync(join(dist, 'overlay.html'))) throw new Error('Build the overlay before running the browser smoke test.');
const profile = mkdtempSync(join(tmpdir(), 'showrunner-browser-smoke-'));
const server = createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).replace(/^\/overlays(?=\/assets\/)/, '');
  const file = pathname.startsWith('/assets/') ? resolve(dist, '.' + pathname) : join(dist, 'overlay.html');
  if (!file.startsWith(dist + sep) || !existsSync(file)) {response.writeHead(404); response.end(); return;}
  response.setHeader('Content-Type', {'.js':'text/javascript', '.css':'text/css', '.html':'text/html'}[extname(file)] ?? 'application/octet-stream');
  response.end(readFileSync(file));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const child = spawn(browser, ['--headless=new', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--use-gl=angle', '--use-angle=swiftshader',
  '--enable-unsafe-swiftshader', 'about:blank'], {windowsHide: true, stdio: 'ignore'});
let socket;
const pending = new Map();
let id = 0;
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function send(method, params = {}) {
  const requestId = ++id;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {pending.delete(requestId); reject(new Error(`CDP timeout: ${method}`));}, 10000);
    pending.set(requestId, {resolve, reject, timer}); socket.send(JSON.stringify({id: requestId, method, params}));
  });
}
async function evaluate(expression) {
  const result = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
try {
  for (let attempt = 0; !existsSync(join(profile, 'DevToolsActivePort')); attempt++) {
    if (attempt > 100) throw new Error('Chromium did not expose its debugging port.');
    await pause(100);
  }
  const port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split(/\r?\n/)[0];
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  socket = new WebSocket(targets.find(target => target.type === 'page').webSocketDebuggerUrl);
  await new Promise((resolve,reject) => {socket.addEventListener('open', resolve, {once:true}); socket.addEventListener('error', reject, {once:true});});
  const errors = [];
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const handler = pending.get(message.id); pending.delete(message.id); clearTimeout(handler.timer);
      message.error ? handler.reject(new Error(JSON.stringify(message.error))) : handler.resolve(message.result);
    } else if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
    else if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') errors.push(message.params.args);
  });
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', {width:640,height:360,deviceScaleFactor:1,mobile:false});
  await send('Page.navigate', {url:`http://127.0.0.1:${server.address().port}/overlays/smoke?demo=1`});
  for (let attempt = 0; !(await evaluate('Boolean(window.showRunnerOverlayRuntime)')); attempt++) {
    if (attempt > 100) throw new Error('Built overlay did not initialize.'); await pause(100);
  }
  const fixture = JSON.parse(readFileSync(join(root, 'test/fixtures/visual-parity/resources.json'), 'utf8')).overlays['parity-overlay'];
  const config = {...fixture, size:{width:640,height:360}, widgets:[{...fixture.widgets[0],size:{width:400,height:80}},
    {id:'browser-shader',plugin:'overlays',widget:'shaderLayer',name:'Shader',visible:true,locked:false,
     position:{x:0,y:120},size:{width:320,height:180},config:{preset:'aurora'}}]};
  await evaluate(`window.showRunnerOverlayRuntime.handleRequest('overlays_setConfig', [${JSON.stringify(config)}])`);
  await pause(250);
  const proof = await evaluate(`(() => {
    const canvas = document.querySelector('.shader-layer__canvas');
    const gl = canvas?.getContext('webgl2') || canvas?.getContext('webgl');
    const label = document.querySelector('[data-widget-id="${fixture.widgets[0].id}"]');
    return {widgets:document.querySelectorAll('.overlay-widget').length, label:label?.innerText,
      canvasWidth:canvas?.width,canvasHeight:canvas?.height,webglReady: Boolean(gl && !gl.isContextLost()),
      renderer:gl?.getParameter(gl.RENDERER),
      shaderLinked:Boolean(window.showRunnerOverlayRuntime.instances.get('browser-shader')?.widget.renderer?.program)};
  })()`);
  if (proof.widgets !== 2 || !proof.label?.includes('LIVE') || !proof.webglReady || !proof.shaderLinked || !proof.canvasWidth || !proof.canvasHeight) {
    throw new Error(`DOM/WebGL rendering failed: ${JSON.stringify(proof)}`);
  }
  config.widgets[0].config.message = 'Browser update verified';
  config.widgets = [config.widgets[0]];
  await evaluate(`window.showRunnerOverlayRuntime.handleRequest('overlays_setConfig', [${JSON.stringify(config)}])`);
  if (!(await evaluate(`document.querySelectorAll('.overlay-widget').length === 1 && document.body.innerText.includes('Browser update verified') && !document.querySelector('canvas')`))) throw new Error('Widget update/removal failed.');
  await evaluate('window.showRunnerOverlayRuntime.stop()');
  if (await evaluate(`document.querySelectorAll('.overlay-widget').length`)) throw new Error('Runtime stop leaked widget elements.');
  if (errors.length) throw new Error(`Browser exceptions: ${JSON.stringify(errors)}`);
  mkdirSync(join(root, '.tmp/overlay-browser'), {recursive:true});
  writeFileSync(join(root, '.tmp/overlay-browser/report.json'), JSON.stringify({...proof, updated:true, stopped:true},null,2));
  console.log('Browser DOM, WebGL, update, removal and shutdown passed:', JSON.stringify(proof));
} finally {
  socket?.close();
  for (const entry of pending.values()) clearTimeout(entry.timer);
  const closed = new Promise(resolve => child.once('exit', resolve));
  child.kill(); await Promise.race([closed, pause(3000)]);
  await new Promise(resolve => server.close(resolve));
  // Only this unique temporary browser profile is removed.
  if (!resolve(profile).startsWith(resolve(tmpdir()) + sep + 'showrunner-browser-smoke-')) {
    throw new Error('Refusing to remove a browser profile outside the temporary test directory.');
  }
  rmSync(profile, {recursive:true,force:true,maxRetries:10,retryDelay:100});
}
