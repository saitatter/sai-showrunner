import { spawnSync } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const scriptDir = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(scriptDir, "..")
const psScript = join(scriptDir, "run-clean-youtube.ps1")
const args = process.argv.slice(2).filter((arg) => arg !== "--")

const result = spawnSync(
	process.platform === "win32" ? "powershell.exe" : "pwsh",
	["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", psScript, ...args],
	{
		cwd: repoRoot,
		stdio: "inherit",
		env: process.env,
	}
)

if (result.error) {
	console.error(result.error.message)
	process.exit(1)
}

process.exit(result.status ?? 1)
