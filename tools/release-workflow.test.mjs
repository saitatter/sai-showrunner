import { readFile } from "node:fs/promises"
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"
import { parse } from "yaml"

const repositoryRoot = resolve(import.meta.dirname, "..")
const workflowPath = resolve(repositoryRoot, ".github/workflows/release.yml")
const proofWorkflowPath = resolve(repositoryRoot, ".github/workflows/release-proof.yml")

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

	it("provides a manual proof workflow on trusted main without publishing", async () => {
		const workflow = await readFile(proofWorkflowPath, "utf8")

		expect(workflow).toContain("workflow_dispatch:")
		expect(workflow).toContain("ref: main")
		expect(workflow).toContain("-SignWindowsBundle")
		expect(workflow).toContain("-RequireWindowsSignature")
		expect(workflow).toContain("package-flutter-windows.ps1")
		expect(workflow).toContain("actions/upload-artifact@v7")
		expect(workflow).not.toContain("gh release upload")
		expect(parse(workflow).jobs["signed-windows-proof"].environment).toBe("release")
	})
})


describe("Manual release policy", () => {
  it("checks the production Debug entrypoint before integration tests replace it", async () => {
    const ci = parse(await readFile(resolve(repositoryRoot, ".github/workflows/ci.yml"), "utf8"))
    const steps = ci.jobs["test-windows"].steps
    const build = steps.findIndex(step => step.name === "Build Flutter Windows debug and release")
    const startup = steps.findIndex(step => step.name === "Smoke Flutter Windows startup")
    const integration = steps.findIndex(step => step.name === "Run Flutter integration gate")
    expect(build).toBeGreaterThan(-1)
    expect(startup).toBeGreaterThan(build)
    expect(integration).toBeGreaterThan(startup)
    expect(steps[startup].run).toContain("-Configuration Debug")
  })
  it("never publishes on pushes or PR merges and validates the planned commit", async () => {
    const workflow = parse(await readFile(workflowPath, "utf8"))
    expect(Object.keys(workflow.on)).toEqual(["workflow_dispatch"])
    expect(workflow.concurrency["cancel-in-progress"]).toBe(false)
    expect(workflow.permissions.contents).toBe("read")
    expect(workflow.jobs.validate.uses).toBe("./.github/workflows/ci.yml")
    expect(workflow.jobs.validate.with.ref).toContain("needs.plan.outputs.commit")
    expect(workflow.jobs.prepare.needs).toContain("validate")
    expect(workflow.jobs["package-windows"].needs).toContain("prepare")
    const steps = workflow.jobs.prepare.steps.map(step => step.run ?? "").join("\n")
    expect(steps).toContain("git push --atomic")
    expect(steps).toContain("--draft --latest=false")
    expect(steps).toContain('test "$(git rev-parse origin/main)" = "$EXPECTED_COMMIT"')
  })
  it("isolates publish credentials and keeps prereleases and backfills out of Latest", async () => {
    const workflow = parse(await readFile(workflowPath, "utf8"))
    expect(workflow.on.workflow_dispatch.inputs).toHaveProperty("dry_run")
    expect(workflow.on.workflow_dispatch.inputs).toHaveProperty("backfill_version")
    const packaging = workflow.jobs["package-windows"]
    expect(packaging.environment).toBe("release")
    const upload = packaging.steps.find(step => step.name === "Upload Windows package")
    expect(upload.run).toContain("if ($env:BACKFILL_VERSION -eq '')")
    expect(upload.run).toContain("'--prerelease', '--latest=false'")
    expect(upload.run.indexOf("gh release upload")).toBeLessThan(upload.run.indexOf("'release', 'edit'"))
    for (const job of Object.values(workflow.jobs)) {
      for (const step of job.steps ?? []) expect(step.run ?? "").not.toMatch(/\$\{\{\s*inputs\./)
    }
  })
  it("matches branch-protection checks and pins the same SDK in every workflow", async () => {
    const ci = parse(await readFile(resolve(repositoryRoot, ".github/workflows/ci.yml"), "utf8"))
    expect(Object.keys(ci.jobs).sort()).toEqual(["release-dry-run", "scripts-ubuntu", "test-windows"])
    expect(ci.on).toHaveProperty("workflow_call")
    for (const name of ["ci", "nightly", "release", "release-proof"]) {
      const source = await readFile(resolve(repositoryRoot, `.github/workflows/${name}.yml`), "utf8")
      const workflow = parse(source)
      for (const job of Object.values(workflow.jobs)) {
        for (const step of job.steps ?? []) {
          if (step.uses?.startsWith("subosito/flutter-action")) expect(step.with["flutter-version"]).toBe("3.47.7")
        }
      }
      expect(source).not.toContain("semantic-release")
    }
  })
})
