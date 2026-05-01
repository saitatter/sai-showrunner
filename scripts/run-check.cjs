const { spawnSync } = require("node:child_process")

function run(command, args, options = {}) {
	const useShell = process.platform === "win32"
	const executable = useShell ? [command, ...args].join(" ") : command
	const result = spawnSync(executable, useShell ? [] : args, {
		stdio: "inherit",
		shell: useShell,
		...options,
	})

	if (result.status !== 0) {
		process.exit(result.status ?? 1)
	}
}

run("corepack", ["yarn", "setup-vite"])
run("node", ["./vite-util/multi-vite.mjs", "build"])
