const fs = require("node:fs")
const path = require("node:path")

const releaseDir = path.resolve(process.argv[2] || "release")

function fail(message) {
	console.error(message)
	process.exitCode = 1
}

function hasFile(predicate) {
	if (!fs.existsSync(releaseDir)) return false
	return fs.readdirSync(releaseDir, { withFileTypes: true }).some((entry) => entry.isFile() && predicate(entry.name))
}

if (!fs.existsSync(releaseDir)) {
	fail(`Release directory does not exist: ${releaseDir}`)
	process.exit()
}

const forbiddenAssets = fs
	.readdirSync(releaseDir, { withFileTypes: true })
	.filter((entry) => entry.isFile() && entry.name === "builder-debug.yml")
	.map((entry) => entry.name)

if (forbiddenAssets.length > 0) {
	fail(`Forbidden release asset found: ${forbiddenAssets.join(", ")}`)
}

if (!hasFile((name) => name.endsWith(".exe"))) fail("Missing Windows installer .exe asset.")
if (!hasFile((name) => name.endsWith(".zip"))) fail("Missing Windows portable .zip asset.")
if (!hasFile((name) => name === "latest.yml")) fail("Missing electron-updater latest.yml asset.")

const asarPath = path.join(releaseDir, "win-unpacked", "resources", "app.asar")
if (!fs.existsSync(asarPath)) {
	fail(`Missing packaged app archive: ${asarPath}`)
} else {
	const stat = fs.statSync(asarPath)
	if (stat.size <= 0) fail(`Packaged app archive is empty: ${asarPath}`)
}

if (!process.exitCode) {
	console.log(`Release artifact smoke passed for ${releaseDir}`)
}
