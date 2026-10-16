import { expect, it } from 'vitest'
import { contractRegressions } from './gate.mjs'

it('rejects missing capabilities even when the plugin still exists', () => {
  expect(contractRegressions({ plugins: [{ id: 'obs', status: 'partial', categories: { actions: { missing: ['setScene'] } }, ui: { status: 'equivalent' } }] })).toEqual(['obs.actions: missing setScene'])
})
it('allows added capabilities and rejects missing UI', () => {
  expect(contractRegressions({ plugins: [{ id: 'obs', status: 'improved', categories: { actions: { missing: [] } }, ui: { status: 'partial' } }] })).toEqual(['obs: missing UI contribution'])
})
