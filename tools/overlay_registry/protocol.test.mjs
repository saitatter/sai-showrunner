import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import { decodeOverlayWire, encodeOverlayWire } from "../../libs/showrunner-overlay-core/src/generated/overlay-protocol.generated"

const fixture = JSON.parse(readFileSync(new URL("../../test/fixtures/overlay-protocol.json", import.meta.url), "utf8"))
describe("canonical overlay wire fixtures", () => {
  for (const [index, {wire, logical}] of fixture.valid.entries()) {
    it(`round trips shared valid envelope ${index}`, () => {
      expect(decodeOverlayWire(wire, fixture.resourceId)).toEqual(logical)
      expect(encodeOverlayWire(logical, fixture.resourceId)).toEqual(wire)
    })
  }
  for (const [index, wire] of fixture.invalid.entries()) {
    it(`rejects shared invalid envelope ${index}`, () => {
      expect(() => decodeOverlayWire(wire, fixture.resourceId)).toThrow("Invalid overlay protocol")
    })
  }
})
