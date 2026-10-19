import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, it } from 'vitest'

it('keeps every native fixture in the single-build suite except explicit live probes', () => {
  const root = resolve(import.meta.dirname, '../packages/showrunner-flutter/integration_test')
  const source = readFileSync(resolve(root, 'native_suite_test.dart'), 'utf8')
  const fixtures = readdirSync(root, { recursive: true })
    .map(path => path.replaceAll('\\', '/'))
    .filter(path => path.endsWith('_test.dart') && !path.split('/').includes('.tmp') && !['native_suite_test.dart', 'visual_capture_test.dart', 'live_nodes_test.dart'].includes(path))
    .sort()
  const imports = [...source.matchAll(/import '([^']+\.dart)'\s+as (\w+);/g)]
    .map(([, path, alias]) => {
      expect(source).toMatch(new RegExp(`\\b${alias}\\.main\\s*[,)]`))
      return path
    }).sort()
  expect(imports).toEqual(fixtures)
})
