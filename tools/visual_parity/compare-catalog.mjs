import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { basename, resolve } from "node:path"
import { spawnSync } from "node:child_process"

const repositoryRoot = resolve(import.meta.dirname, "../..")
const manifestPath = resolve(repositoryRoot, "tools/visual_parity/catalog.json")
const compareScript = resolve(repositoryRoot, "tools/visual_parity/compare.mjs")
const outputRoot = resolve(repositoryRoot, ".tmp/visual/catalog")
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
const options = new Map(
	process.argv.slice(2).flatMap((argument) => {
		if (!argument.startsWith("--")) return []
		const separator = argument.indexOf("=")
		return separator < 0
			? [[argument.slice(2), "true"]]
			: [[argument.slice(2, separator), argument.slice(separator + 1)]]
	}),
)
const channelThreshold = Number(options.get("channel-threshold") ?? 0)
const failAbove = options.has("fail-above") ? Number(options.get("fail-above")) : undefined
const actualRoot = options.has("actual-root")
	? resolve(repositoryRoot, options.get("actual-root"))
	: undefined

if (!Number.isFinite(channelThreshold) || channelThreshold < 0 || channelThreshold > 255) {
	throw new Error("--channel-threshold must be between 0 and 255")
}
if (failAbove !== undefined && (!Number.isFinite(failAbove) || failAbove < 0 || failAbove > 100)) {
	throw new Error("--fail-above must be between 0 and 100")
}

mkdirSync(outputRoot, { recursive: true })
const results = []
const failures = []

function reportFrom(result, pairId, scope) {
	const reportLine = result.stdout
		.trim()
		.split(/\r?\n/)
		.find((line) => line.startsWith("{"))
	if (!reportLine) {
		failures.push(`${pairId}: ${scope} comparison failed: ${result.stderr.trim() || "unknown error"}`)
		return undefined
	}
	return JSON.parse(reportLine)
}

for (const pair of manifest.pairs) {
	const reference = resolve(repositoryRoot, pair.reference)
	const actual = actualRoot
		? resolve(actualRoot, basename(pair.actual))
		: resolve(repositoryRoot, pair.actual)
	const diff = resolve(outputRoot, `${pair.id}.diff.png`)
	const reportPath = resolve(outputRoot, `${pair.id}.json`)
if (!existsSync(reference) || !existsSync(actual)) {
		failures.push(`${pair.id}: reference or actual PNG is missing`)
		continue
	}

	const result = spawnSync(
		process.execPath,
		[
			compareScript,
			`--reference=${reference}`,
			`--actual=${actual}`,
			`--diff=${diff}`,
			`--report=${reportPath}`,
			`--channel-threshold=${channelThreshold}`,
			"--max-difference=100",
		],
		{ cwd: repositoryRoot, encoding: "utf8" },
	)
	const report = reportFrom(result, pair.id, "full-screen")
	if (!report) continue
	let diagnosticRegion
	if (pair.diagnosticRegion) {
		const region = pair.diagnosticRegion
		const regionResult = spawnSync(
			process.execPath,
			[
				compareScript,
				`--reference=${reference}`,
				`--actual=${actual}`,
				`--diff=${resolve(outputRoot, `${pair.id}.workspace.diff.png`)}`,
				`--report=${resolve(outputRoot, `${pair.id}.workspace.json`)}`,
				`--channel-threshold=${channelThreshold}`,
				"--max-difference=100",
				`--region=${region.x},${region.y},${region.width},${region.height}`,
			],
			{ cwd: repositoryRoot, encoding: "utf8" },
		)
		const regionReport = reportFrom(regionResult, pair.id, "workspace-region")
		if (regionReport) {
			diagnosticRegion = {
				label: region.label,
				x: region.x,
				y: region.y,
				width: regionReport.width,
				height: regionReport.height,
				differencePercent: regionReport.differencePercent,
				meanChannelDelta: regionReport.meanChannelDelta,
				diff: resolve(outputRoot, `${pair.id}.workspace.diff.png`),
				report: resolve(outputRoot, `${pair.id}.workspace.json`),
			}
		}
	}
	results.push({
		id: pair.id,
		actual,
		differencePercent: report.differencePercent,
		meanChannelDelta: report.meanChannelDelta,
		...(diagnosticRegion ? { diagnosticRegion } : {}),
		diff,
		report: reportPath,
	})
	if (failAbove !== undefined && report.differencePercent > failAbove) {
		failures.push(
			`${pair.id}: ${report.differencePercent}% differs, threshold is ${failAbove}%`,
		)
	}
}

const summary = {
	captureSize: manifest.captureSize,
	channelThreshold,
	failAbove: failAbove ?? null,
	results,
	failures,
}
const summaryPath = resolve(outputRoot, "summary.json")
writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`)
console.log(JSON.stringify({ ...summary, summary: summaryPath }, null, 2))
if (failures.length > 0) process.exitCode = 1
