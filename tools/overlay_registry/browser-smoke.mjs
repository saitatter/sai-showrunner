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
const dockToken = 'isolated-browser-smoke-token';
const dockMessages = [
  {identity:'twitch:channel:1', platform:'twitch', viewerId:'same-id', viewerName:'Twitch Viewer', message:'Hello from Twitch', isOwner:false, deleted:false},
  {identity:'youtube:live:2', platform:'youtube', viewerId:'same-id', viewerName:'<b>YouTube Viewer</b>', message:'<script>window.chatXss=true</script>', isOwner:false, deleted:false},
];
const dockRequests = [];
const server = createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).replace(/^\/overlays(?=\/assets\/)/, '');
  if (pathname.startsWith('/api/')) {
    if (request.headers['x-showrunner-chat'] !== dockToken) {response.writeHead(401); response.end(); return;}
    response.setHeader('Content-Type', 'application/json');
    if (pathname === '/api/chat') {response.end(JSON.stringify({messages:dockMessages, completions:{twitch:[{text:'!hello',label:'!hello - Hello',kind:'command'},{text:'!hi',label:'!hi - Hello',kind:'command'},{text:'/pause',label:'/pause',kind:'action'},{text:'/resume',label:'/resume',kind:'action'},{text:'\u{1f600}',label:':smile:',kind:'emote'}],youtube:[{text:'\u{1f600}',label:':smile:',kind:'emote'}]}, emotes:[{name:':smile:',text:'😀'}]})); return;}
    let body = ''; for await (const chunk of request) body += chunk;
    dockRequests.push({path:pathname, ...JSON.parse(body)});
    response.end(JSON.stringify({ok:true})); return;
  }
  const file = pathname.startsWith('/assets/') ? resolve(dist, '.' + pathname) : join(dist, pathname === '/chat-dock' ? 'chat-dock.html' : 'overlay.html');
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
  await send('Page.navigate', {url:`http://127.0.0.1:${server.address().port}/chat-dock#${dockToken}`});
  for (let attempt = 0; !(await evaluate('document.querySelectorAll("article").length === 2')); attempt++) {
    if (attempt > 100) throw new Error('Chat dock did not load shared history.'); await pause(100);
  }
  if (await evaluate('Boolean(window.chatXss) || document.querySelector("article b") !== null')) throw new Error('Chat dock interpreted a message or user name as HTML.');
  await evaluate(`document.querySelector('#filter').value='twitch'; document.querySelector('#filter').dispatchEvent(new Event('change'))`);
  if (!(await evaluate('document.querySelectorAll("article").length === 1 && document.querySelector("article").textContent.includes("Twitch Viewer")'))) throw new Error('Chat dock platform filter failed.');
  await evaluate(`document.querySelector('#platform').value='youtube'; document.querySelector('#message').value='Browser dock message'; document.querySelector('#composer').requestSubmit()`);
  for (let attempt = 0; dockRequests.length !== 1; attempt++) {
    if (attempt > 100) throw new Error('Chat dock composer did not send.'); await pause(100);
  }
  if (dockRequests[0].platform !== 'youtube' || dockRequests[0].message !== 'Browser dock message') throw new Error('Chat dock sent to the wrong platform.');
  for (let attempt = 0; !(await evaluate('!document.querySelector("#composer button").disabled')); attempt++) {
    if (attempt > 100) throw new Error('Chat dock composer did not finish sending.'); await pause(100);
  }
  await evaluate(`document.querySelector('#message').value=':smi'; document.querySelector('#message').setSelectionRange(4,4); document.querySelector('#message').dispatchEvent(new Event('input')); document.querySelector('#emotes button').click()`);
  if (!(await evaluate(`document.querySelector('#message').value === '😀 '`))) throw new Error('Chat dock emote autocomplete failed.');
  await evaluate(`const menu=document.querySelector('article select'); menu.value='reply'; menu.dispatchEvent(new Event('change'))`);
  if (!(await evaluate(`document.querySelector('#platform').value === 'twitch' && document.querySelector('#message').value === '@Twitch Viewer '`))) throw new Error('Chat dock reply target failed.');
  await evaluate(`document.querySelector('#message').value='!h'; document.querySelector('#message').setSelectionRange(2,2); document.querySelector('#message').dispatchEvent(new Event('input'))`);
  if (!(await evaluate(`document.querySelectorAll('#emotes button').length === 2`))) throw new Error('Managed command aliases missing from dock menu.');
  await evaluate(`document.querySelector('#message').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true})); document.querySelector('#message').dispatchEvent(new KeyboardEvent('keydown',{key:'Tab',bubbles:true}))`);
  if (!(await evaluate(`document.querySelector('#message').value === '!hi '`))) throw new Error('Dock keyboard command completion failed.');
  await evaluate(`document.querySelector('#message').value='/pause'; document.querySelector('#composer').requestSubmit()`);
  await pause(50);
  dockMessages.push({identity:'twitch:channel:late',platform:'twitch',viewerId:'late',viewerName:'Late',message:'Incoming during pause',isOwner:false,deleted:false});
  await pause(1100);
  if (await evaluate(`document.querySelector('#messages').textContent.includes('Incoming during pause')`)) throw new Error('Paused dock rendered new arrivals.');
  await evaluate(`document.querySelector('#message').value='/resume'; document.querySelector('#composer').requestSubmit()`);
  await pause(50);
  if (!(await evaluate(`document.querySelector('#messages').textContent.includes('Incoming during pause')`))) throw new Error('Resumed dock did not show arrivals.');
  if (dockRequests.length !== 1) throw new Error('Local slash actions leaked to provider send endpoint.');
  const screenshot = await send('Page.captureScreenshot', {format:'png'});
  writeFileSync(join(root, '.tmp/overlay-browser/chat-dock.png'), Buffer.from(screenshot.data, 'base64'));
  if (errors.length) throw new Error(`Chat dock browser exceptions: ${JSON.stringify(errors)}`);
  console.log('Chat dock history, HTML safety, platform filter, composer, emote/command keyboard completion, local pause/resume and reply passed.');
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
