const fs = require("node:fs")
const path = require("node:path")

const distDir = path.resolve(process.argv[2] || "packages/showrunner/dist")
const assetsDir = path.join(distDir, "assets")
const htmlPath = path.join(distDir, "html", "index.html")

function fail(message) {
	console.error(message)
	process.exitCode = 1
}

function readIfExists(file) {
	return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : ""
}

if (!fs.existsSync(htmlPath)) fail(`Missing renderer HTML: ${htmlPath}`)
if (!fs.existsSync(assetsDir)) fail(`Missing renderer assets: ${assetsDir}`)

const assetText = fs.existsSync(assetsDir)
	? fs
			.readdirSync(assetsDir)
			.filter((name) => /\.(js|css)$/.test(name))
			.map((name) => readIfExists(path.join(assetsDir, name)))
			.join("\n")
	: ""
const packagedText = `${readIfExists(htmlPath)}\n${assetText}`

const requiredMarkers = [
	["Settings page", "Interface"],
	["Updates page", "Current version"],
	["Integrations page", "Integrations"],
	["starter template menu", "New Automation From Starter"],
	["queue starter template", "Paid Event -> Add to Alerts Queue"],
	["graph editor shell", "node-automation"],
]

for (const [label, marker] of requiredMarkers) {
	if (!packagedText.includes(marker)) fail(`Packaged renderer is missing ${label} marker: ${marker}`)
}

if (!process.exitCode) {
	console.log(`Packaged beta UI smoke passed for ${distDir}`)
}
