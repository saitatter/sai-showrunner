import { readFile } from "node:fs/promises"
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"

const repositoryRoot = resolve(import.meta.dirname, "..")
const workflowPath = resolve(repositoryRoot, ".github/workflows/release.yml")

describe("Windows release workflow", () => {
	it("refuses to package or publish an unsigned Windows build", async () => {
		const workflow = await readFile(workflowPath, "utf8")

		expect(workflow).toContain("'-SignWindowsBundle'")
		expect(workflow).toContain("'-RequireWindowsSignature'")
		expect(workflow).toContain("SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_BASE64")
		expect(workflow).toContain("SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_PASSWORD")
		expect(workflow).toContain("throw 'Windows signing secrets are required for a release package.'")
	})

	it("builds the browser overlay and runs the updater proof before upload", async () => {
		const workflow = await readFile(workflowPath, "utf8")
		const overlayBuild = workflow.indexOf("run: yarn overlay:build")
		const packageStep = workflow.indexOf("-RequireWindowsSignature")
		const uploadStep = workflow.indexOf("name: Upload Windows package")

		expect(overlayBuild).toBeGreaterThan(-1)
		expect(packageStep).toBeGreaterThan(overlayBuild)
		expect(workflow).toContain("Protected Windows signing secrets detected; running signed package and updater proof.")
		expect(uploadStep).toBeGreaterThan(packageStep)
		expect(workflow.slice(packageStep, uploadStep)).toContain("package-flutter-windows.ps1")
	})
})
