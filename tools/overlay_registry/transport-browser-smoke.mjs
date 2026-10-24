import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { launchChromium } from './chromium-launcher.mjs';

const root = resolve(import.meta.dirname, '../..');
const scratch = join(root, '.tmp/protocols', `browser-transport-${Date.now()}`);
mkdirSync(scratch, {recursive:true});
const child = spawn(process.platform === 'win32' ? 'cmd.exe' : 'flutter',
  process.platform === 'win32' ? ['/d','/s','/c','flutter test tool/overlay_browser_smoke_host_test.dart'] : ['test','tool/overlay_browser_smoke_host_test.dart'],
  {cwd:join(root,'packages/showrunner-flutter'),env:{...process.env,SHOWRUNNER_OVERLAY_SMOKE_DIRECTORY:scratch},windowsHide:true});
const exited = new Promise((resolve, reject) => { child.once('error',reject); child.once('exit',resolve); });
// Observe startup failures before the browser reaches the wait below.
exited.catch(() => {});
child.stdout.on('data',chunk => appendFileSync(join(scratch,'host.log'),chunk));
child.stderr.on('data',chunk => appendFileSync(join(scratch,'host.log'),chunk));
let browser, socket;
let nextId = 0;
const pending = new Map();
async function send(method, params={}) {
  const id = ++nextId;
  return new Promise((resolve,reject) => {
    const timer = setTimeout(() => {pending.delete(id);reject(new Error(`Browser command expired: ${method}`));},10000);
    pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));
  });
}
async function evaluate(expression) {
  const result = await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});
  if (result.exceptionDetails) throw new Error('Browser transport evaluation failed.');
  return result.result.value;
}
try {
  const deadline = Date.now()+20000;
  while (!existsSync(join(scratch,'host.json'))) {
    if (Date.now()>deadline || child.exitCode !== null) throw new Error('Isolated Dart overlay host did not start.');
    await pause(50);
  }
  const {url} = JSON.parse(readFileSync(join(scratch,'host.json'),'utf8'));
  const publicUrl = new URL(url); publicUrl.hash = '';
  const denied = await fetch(new URL(`${publicUrl.pathname}/config`,publicUrl));
  if (denied.status !== 401) throw new Error('Unauthenticated config was not rejected.');
  browser = await launchChromium();
  const targets = await (await fetch(`http://127.0.0.1:${browser.port}/json/list`)).json();
  socket = new WebSocket(targets.find(target=>target.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
  socket.addEventListener('message',event=>{
    const message=JSON.parse(event.data), call=pending.get(message.id);
    if (!call) return;
    pending.delete(message.id);clearTimeout(call.timer);
    if (message.error) call.reject(new Error('Browser command failed.')); else call.resolve(message.result);
  });
  await send('Page.enable');await send('Runtime.enable');
  await send('Page.navigate',{url});
  const connectedDeadline=Date.now()+10000;
  while (!await evaluate(`document.body.innerText.includes('Authenticated bridge connected') && document.body.innerText.includes('Public Viewer') && document.body.innerText.includes('42')`)) {
    if (Date.now()>connectedDeadline) throw new Error('Authenticated WebSocket config did not render.');
    await pause(50);
  }
  const proof = await evaluate(`(async()=>{
    const config=await fetch('/overlays/browser-probe/config');
    const foreign=await fetch('/overlays/another/config');
    const runtime=window.showRunnerOverlayRuntime;
    const rows=await runtime.callBackend('overlays_queryViewerData',0,5,'score',-1);
    const variables=await runtime.callBackend('overlays_getViewerVariables');
    const result={config:config.status,foreign:foreign.status,rows:rows.length,score:rows[0]?.score,variables:variables.map(value=>value.name),privateExcluded:!JSON.stringify(rows).includes('private-browser-marker') && !document.body.innerText.includes('private-browser-marker'),widgets:document.querySelectorAll('.overlay-widget').length,cookieHidden:!document.cookie.includes('showrunner-overlay')};
    await runtime.stop();
    return result;
  })()`);
  if (proof.config!==200 || proof.foreign!==401 || proof.rows!==1 || proof.score!==42 || proof.widgets!==2 || proof.variables.join()!=='score' || !proof.privateExcluded || !proof.cookieHidden) throw new Error('Authenticated browser isolation proof failed.');
  writeFileSync(join(scratch,'report.json'),JSON.stringify(proof,null,2));
  console.log('Real Dart/Chromium bootstrap, HttpOnly cookie, scoped config, versioned WebSocket RPC and shutdown passed.');
} finally {
  for (const call of pending.values()) {clearTimeout(call.timer);call.reject(new Error('Browser smoke closed.'));}
  pending.clear();
  socket?.close();
  await browser?.close();
  writeFileSync(join(scratch,'done'),'done');
  if (await exited !== 0) throw new Error('Isolated Dart overlay host failed.');
}
