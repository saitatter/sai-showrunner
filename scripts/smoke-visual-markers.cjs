const fs = require("node:fs")
const path = require("node:path")

const distDir = path.resolve(process.argv[2] || "packages/showrunner/dist")
const assetsDir = path.join(distDir, "assets")

function fail(message) {
	console.error(message)
	process.exitCode = 1
}

if (!fs.existsSync(assetsDir)) {
	fail(`Missing renderer assets: ${assetsDir}`)
	process.exit()
}

const files = fs.readdirSync(assetsDir).filter((name) => /\.(js|css)$/.test(name))
const bundleText = files.map((name) => fs.readFileSync(path.join(assetsDir, name), "utf8")).join("\n")

const visualMarkers = [
	["settings interface section", "settings-page__section-actions"],
	["updates status card", "updates-page__status--available"],
	["integration detail search", "plugin-details__search"],
	["integration toggle states", "plugin-details__toggle.enabled"],
	["integration compact rows", "plugin-details__chips"],
	["automation hidden plugin hint", "node-automation__menu-hint"],
	["automation context menu", "node-automation__context-menu"],
	["automation annotation blocks", "node-automation__annotation-block"],
	["automation annotation drag remove feedback", "node-automation__annotation-block.remove-target"],
	["automation flow edge health", "invalid sequence edge"],
	["automation graph health panel", "Graph Health"],
	["shader graph palette", "shader-graph__palette"],
	["shader graph side panel", "shader-graph__side-panel"],
	["shader graph preview fallback", "shader-graph__preview-overlay"],
	["shader graph frame controls", "shader-graph__frame-resize"],
	["shader graph minimap", "shader-graph__minimap"],
	["shader graph issue highlights", "shader-graph__wire--issue"],
]

for (const [label, marker] of visualMarkers) {
	if (!bundleText.includes(marker)) fail(`Missing visual marker for ${label}: ${marker}`)
}

if (!process.exitCode) {
	console.log(`Visual marker smoke passed for ${distDir}`)
}
