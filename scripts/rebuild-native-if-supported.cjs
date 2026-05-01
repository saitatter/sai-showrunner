const { spawnSync } = require("node:child_process")

if (process.platform !== "win32") {
	console.log(`Skipping native rebuild on ${process.platform}; this package is built for Windows packaging.`)
	process.exit(0)
}

const nodeGyp = require.resolve("node-gyp/bin/node-gyp.js")
const result = spawnSync(process.execPath, [nodeGyp, "rebuild"], {
	stdio: "inherit",
	shell: false,
})

process.exit(result.status ?? 1)
