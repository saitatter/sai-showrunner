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
if (!existsSync(join(root, 'packages/showrunner-flutter/.tmp/shader-catalog.json'))) {
  throw new Error('Export fixtures: SHOWRUNNER_EXPORT_SHADER_FIXTURES=1 flutter test test/plugins/overlays/shader_graph_test.dart');
}
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
  const fixtures = JSON.parse(readFileSync(join(root, 'packages/showrunner-flutter/.tmp/shader-catalog.json'), 'utf8'));
  await evaluate(`window.showRunnerOverlayRuntime.handleRequest('overlays_setConfig', [{size:{width:320,height:180},widgets:[{id:'shader',visible:true,locked:false,plugin:'overlays',widget:'shaderLayer',position:{x:0,y:0},size:{width:320,height:180},config:{preset:'aurora'}}]}])`);
  await pause(300);
  const results = await evaluate(`(() => {
    const renderer = window.showRunnerOverlayRuntime.instances.get('shader').widget.renderer;
    if (!renderer) throw new Error('Production shader renderer missing');
    const gl = renderer.gl;
    return ${JSON.stringify(fixtures)}.map(fixture => {
      const error = renderer.compileShader(fixture.glsl);
      if(error) return {id:fixture.id,error};
      renderer.options.getCustomUniforms = () => fixture.uniforms;
      cancelAnimationFrame(renderer.animationFrame);
      renderer.render();
      const pixels = new Uint8Array(4*320*180);
      gl.readPixels(0,0,320,180,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
      let sum=0,nonzero=0;
      for(let i=0;i<pixels.length;i+=4) {sum+=pixels[i]+pixels[i+1]+pixels[i+2]; if(pixels[i]+pixels[i+1]+pixels[i+2]>0) nonzero++;}
      return {id:fixture.id,linked:gl.getProgramParameter(renderer.program,gl.LINK_STATUS),glError:gl.getError(),sum,nonzero};
    });
  })()`);
  mkdirSync(join(root,'.tmp/shader-catalog'),{recursive:true});
  writeFileSync(join(root,'.tmp/shader-catalog/report.json'),JSON.stringify({results,errors},null,2));
  const failed=results.filter(r=>r.error || !r.linked || r.glError);
  console.log(JSON.stringify({count:results.length,failed,starters:results.filter(r=>r.id.startsWith('starter-'))},null,2));
  if(failed.length || errors.length) throw new Error('Shader catalog WebGL failures; see .tmp/shader-catalog/report.json');
  await evaluate('window.showRunnerOverlayRuntime.stop()');
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
