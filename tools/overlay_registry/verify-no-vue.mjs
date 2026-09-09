import { readFile, readdir } from "node:fs/promises"
import { join, relative, resolve } from "node:path"

const root = resolve(import.meta.dirname, "../..")
const overlayRoots = [
	"packages/showrunner-obs-overlay",
	"libs/showrunner-overlay-core",
	"libs/showrunner-overlay-widget-loader",
	"plugins/overlays/overlay",
	"plugins/random/overlay",
	"plugins/twitch/overlay",
]

const violations = []

for (const relativeRoot of overlayRoots) {
	const packagePath = join(root, relativeRoot, "package.json")
	const packageJson = JSON.parse(await readFile(packagePath, "utf8"))
	for (const dependencyGroup of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
		for (const dependency of Object.keys(packageJson[dependencyGroup] ?? {})) {
			if (dependency === "vue" || dependency === "pinia" || dependency.startsWith("@vue/")) {
				violations.push(`${relative(packagePath, root)}: forbidden dependency ${dependency}`)
			}
		}
	}

	await scan(join(root, relativeRoot))
}

if (violations.length > 0) {
	console.error("Overlay runtime must remain Vue-free:")
	for (const violation of violations) console.error(`- ${violation}`)
	process.exitCode = 1
} else {
	console.log(`Overlay runtime is Vue-free (${overlayRoots.length} workspaces checked).`)
}

async function scan(directory) {
	for (const entry of await readdir(directory, { withFileTypes: true })) {
		if (entry.name === "node_modules" || entry.name === "dist" || entry.name === ".git") continue
		const path = join(directory, entry.name)
		if (entry.isDirectory()) {
			await scan(path)
			continue
		}
		if (!entry.isFile()) continue
		if (entry.name.endsWith(".vue")) {
			violations.push(`${relative(path, root)}: Vue component file`)
			continue
		}
		if (!/\.(?:ts|tsx|js|mjs|cjs)$/.test(entry.name)) continue
		const source = await readFile(path, "utf8")
		if (/(?:from|require\s*\()\s*["'](?:vue|pinia)(?:["']|\/)/.test(source)) {
			violations.push(`${relative(path, root)}: Vue/Pinia import`)
		}
	}
}
