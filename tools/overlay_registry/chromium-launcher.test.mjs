import { EventEmitter } from 'node:events';
import { existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { launchChromium } from './chromium-launcher.mjs';

function fakeProcess(onStart) {
  const child = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kill = () => {
    child.signalCode = 'SIGTERM';
    child.emit('exit', null, 'SIGTERM');
    return true;
  };
  queueMicrotask(() => onStart(child));
  return child;
}
const ready = async () => ({ ok: true, json: async () => ({
  Browser: 'Chromium fixture', webSocketDebuggerUrl: 'ws://127.0.0.1:12345/devtools/browser/test',
}) });

describe('isolated Chromium startup', () => {
  it('uses the stderr endpoint when no DevToolsActivePort file is written', async () => {
    const requests = [];
    const session = await launchChromium({
      candidates: ['chromium-fixture'], report: () => {},
      spawnProcess: (_, args, options) => {
        expect(options.windowsHide).toBe(true);
        expect(args).toContain('--headless=new');
        return fakeProcess(child => child.stderr.emit('data', 'DevTools listening on ws://127.0.0.1:12345/devtools/browser/test\n'));
      },
      fetchEndpoint: async url => { requests.push(url); return ready(); },
    });
    try {
      expect(session.port).toBe(12345);
      expect(requests).toContain('http://127.0.0.1:12345/json/version');
      expect(existsSync(join(session.profile, 'DevToolsActivePort'))).toBe(false);
    } finally { await session.close(); }
    expect(existsSync(session.profile)).toBe(false);
  });

  it('tries another installed browser only when startup fails and preserves diagnostics', async () => {
    const profiles = [], reports = [];
    const session = await launchChromium({
      candidates: ['broken-browser', 'working-browser'], report: message => reports.push(message),
      fetchEndpoint: ready,
      spawnProcess: (binary, args) => {
        const profile = args.find(arg => arg.startsWith('--user-data-dir=')).split('=')[1];
        profiles.push(profile);
        return fakeProcess(child => {
          if (binary === 'broken-browser') {
            child.stderr.emit('data', 'Sandbox startup failed');
            child.exitCode = 17;
            child.emit('exit', 17, null);
          } else {
            writeFileSync(join(profile, 'DevToolsActivePort'), '12345\n/devtools/browser/test');
          }
        });
      },
    });
    try {
      expect(profiles).toHaveLength(2);
      expect(profiles[0]).not.toBe(profiles[1]);
      expect(existsSync(profiles[0])).toBe(false);
      expect(reports.join('\n')).toContain('code 17');
      expect(reports.join('\n')).toContain('Sandbox startup failed');
    } finally { await session.close(); }
    expect(profiles.every(profile => !existsSync(profile))).toBe(true);
  });

  it('rejects an unresponsive advertised endpoint instead of passing readiness', async () => {
    let profile;
    await expect(launchChromium({
      candidates: ['unresponsive-browser'], timeoutMs: 30, report: () => {},
      spawnProcess: (_, args) => {
        profile = args.find(arg => arg.startsWith('--user-data-dir=')).split('=')[1];
        return fakeProcess(child => child.stderr.emit('data', 'DevTools listening on ws://127.0.0.1:12345/devtools/browser/test\n'));
      },
      fetchEndpoint: async () => ({ ok: false }),
    })).rejects.toThrow('responsive debugging endpoint');
    expect(existsSync(profile)).toBe(false);
  });

  it('surfaces spawn errors and cleans the unused isolated profile', async () => {
    let profile;
    await expect(launchChromium({
      candidates: ['missing-browser'], report: () => {},
      spawnProcess: (_, args) => {
        profile = args.find(arg => arg.startsWith('--user-data-dir=')).split('=')[1];
        return fakeProcess(child => child.emit('error', new Error('ENOENT fixture')));
      },
    })).rejects.toThrow('ENOENT fixture');
    expect(existsSync(profile)).toBe(false);
  });
});
