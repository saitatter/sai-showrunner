import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs"
import { basename, resolve } from "node:path"
import { spawnSync } from "node:child_process"
import { describe, expect, it } from "vitest"

const repositoryRoot = resolve(import.meta.dirname, "../..")
const manifestPath = resolve(repositoryRoot, "tools/visual_parity/catalog.json")
const scriptPath = resolve(repositoryRoot, "tools/visual_parity/compare-catalog.mjs")
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))

describe("visual parity catalog", () => {
	it("keeps every comparison pair backed by captured PNGs", () => {
		expect(manifest.captureSize).toEqual({ width: 1440, height: 900, deviceScaleFactor: 1 })
		expect(manifest.pairs.length).toBeGreaterThanOrEqual(8)
		for (const pair of manifest.pairs) {
			expect(existsSync(resolve(repositoryRoot, pair.reference))).toBe(true)
			expect(existsSync(resolve(repositoryRoot, pair.actual))).toBe(true)
		}
	})

	it("produces a report for the complete catalog without hiding differences", () => {
		const result = spawnSync(process.execPath, [scriptPath], {
			cwd: repositoryRoot,
			encoding: "utf8",
		})
		expect(result.status).toBe(0)
		const report = JSON.parse(result.stdout)
		expect(report.results).toHaveLength(manifest.pairs.length)
		expect(report.failures).toEqual([])
		expect(report.results.every(({ differencePercent }) => differencePercent >= 0)).toBe(true)
	})

	it("compares captures from the supplied current-build directory", () => {
		const actualRoot = resolve(repositoryRoot, ".tmp/visual/catalog-test-actuals")
		mkdirSync(actualRoot, { recursive: true })
		for (const pair of manifest.pairs) {
			copyFileSync(
				resolve(repositoryRoot, pair.actual),
				resolve(actualRoot, basename(pair.actual)),
			)
		}

		const result = spawnSync(
			process.execPath,
			[scriptPath, `--actual-root=${actualRoot}`],
			{ cwd: repositoryRoot, encoding: "utf8" },
		)
		expect(result.status).toBe(0)
		const report = JSON.parse(result.stdout)
		expect(report.results).toHaveLength(manifest.pairs.length)
		expect(report.results[0].actual).toBe(
			resolve(actualRoot, basename(manifest.pairs[0].actual)),
		)
	})
})
