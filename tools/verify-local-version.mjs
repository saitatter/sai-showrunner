import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root = resolve(import.meta.dirname, '..');
const version = JSON.parse(readFileSync(resolve(root, 'package.json'),'utf8')).version;
const pubspec = readFileSync(resolve(root,'packages/showrunner-flutter/pubspec.yaml'),'utf8').match(/^version:\s*([^+\s]+)/m)?.[1];
const fallback = readFileSync(resolve(root,'packages/showrunner-flutter/lib/services/update_check_service.dart'),'utf8').match(/SHOWRUNNER_VERSION'[\s\S]*?defaultValue:\s*'([^']+)'/)?.[1];
if (pubspec !== version || fallback !== version) throw new Error(`Local version mismatch: root=${version}, Flutter=${pubspec}, updater=${fallback}`);
console.log(`Local version defaults agree: ${version}`);
