import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { join, resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { setTimeout as pause } from 'node:timers/promises';

const profilePrefix = join(tmpdir(), 'showrunner-browser-smoke-');
const defaultBinaries = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/chromium', '/usr/bin/google-chrome',
];

// Startup fallback only: callers run their assertions once on the ready browser.
export async function launchChromium({
  candidates = process.env.SHOWRUNNER_CHROMIUM_BINARY
    ? [process.env.SHOWRUNNER_CHROMIUM_BINARY] : defaultBinaries.filter(existsSync),
  spawnProcess = spawn, fetchEndpoint = fetch, timeoutMs = 10000,
  report = console.log,
} = {}) {
  if (!candidates.length) throw new Error('Set SHOWRUNNER_CHROMIUM_BINARY to a Chrome or Edge executable.');
  const failures = [];
  for (const binary of candidates) {
    const profile = mkdtempSync(profilePrefix);
    let child, spawnError, stderr = '';
    const close = async () => {
      if (child && child.exitCode === null && child.signalCode === null && !spawnError) {
        const exited = new Promise(resolve => child.once('exit', resolve));
        child.kill();
        await Promise.race([exited, pause(3000, undefined, { ref: false })]);
        if (child.exitCode === null && child.signalCode === null) {
          throw new Error(`Browser did not stop; retained isolated profile: ${profile}`);
        }
      }
      if (!resolve(profile).startsWith(resolve(tmpdir()) + sep + 'showrunner-browser-smoke-')) {
        throw new Error('Refusing to remove a browser profile outside the temporary test directory.');
      }
      rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
    };
    try {
      child = spawnProcess(binary, [
        '--headless=new', '--no-first-run', '--no-default-browser-check',
        '--remote-debugging-port=0', `--user-data-dir=${profile}`,
        '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', 'about:blank',
      ], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
      child.once('error', error => { spawnError = error; });
      child.stderr.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(-8192); });
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        if (spawnError) throw spawnError;
        if (child.exitCode !== null || child.signalCode !== null) {
          throw new Error(`Browser exited (code ${child.exitCode}, signal ${child.signalCode}).`);
        }
        // Some Chromium builds announce CDP on stderr before/without writing
        // DevToolsActivePort. Neither signal is success until HTTP CDP responds.
        let port = stderr.match(/DevTools listening on ws:\/\/(?:127\.0\.0\.1|localhost):(\d+)\//)?.[1];
        if (!port && existsSync(join(profile, 'DevToolsActivePort'))) {
          port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split(/\r?\n/)[0];
        }
        if (port && /^\d+$/.test(port) && Number(port) > 0 && Number(port) <= 65535) {
          try {
            const response = await fetchEndpoint(`http://127.0.0.1:${port}/json/version`, {
              signal: AbortSignal.timeout(Math.max(1, Math.min(1000, deadline - Date.now()))),
            });
            const version = response.ok ? await response.json() : null;
            if (version?.webSocketDebuggerUrl) {
              report(`Chromium ready: ${binary} (${version.Browser ?? 'CDP'})`);
              return { child, profile, port: Number(port), close };
            }
          } catch { /* The endpoint may still be starting; keep the same deadline. */ }
        }
        await pause(Math.min(100, Math.max(0, deadline - Date.now())));
      }
      throw new Error(`Chromium did not expose a responsive debugging endpoint within ${timeoutMs} ms.`);
    } catch (error) {
      const diagnostic = `${binary}: ${error.message}\n${stderr || '(no browser stderr)'}`;
      failures.push(diagnostic);
      report(`Chromium startup failed: ${diagnostic}`);
      await close();
    }
  }
  throw new Error(`No Chromium browser could start:\n${failures.join('\n')}`);
}
