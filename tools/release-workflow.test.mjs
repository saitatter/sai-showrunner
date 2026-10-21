import { readFile } from "node:fs/promises"
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"
import { parse } from "yaml"

const repositoryRoot = resolve(import.meta.dirname, "..")
const workflowPath = resolve(repositoryRoot, ".github/workflows/release.yml")
const proofWorkflowPath = resolve(repositoryRoot, ".github/workflows/release-proof.yml")

describe("Windows release workflow", () => {
	it("packages unsigned Windows releases without certificate credentials", async () => {
		const workflow = await readFile(workflowPath, "utf8")

		expect(workflow).not.toContain("-SignWindowsBundle")
		expect(workflow).not.toContain("-RequireWindowsSignature")
		expect(workflow).not.toContain("SIGNING_CERTIFICATE")
		expect(workflow).toContain("Packaging unsigned Windows binaries")
	})

	it("builds the browser overlay and runs the updater proof before upload", async () => {
		const workflow = await readFile(workflowPath, "utf8")
		const overlayBuild = workflow.indexOf("run: yarn overlay:build")
		const packageStep = workflow.indexOf("name: Build and smoke-test Windows package")
		const uploadStep = workflow.indexOf("name: Upload Windows package")

		expect(overlayBuild).toBeGreaterThan(-1)
		expect(packageStep).toBeGreaterThan(overlayBuild)
		expect(workflow).toContain("running application/updater proofs.")
		expect(uploadStep).toBeGreaterThan(packageStep)
		expect(workflow.slice(packageStep, uploadStep)).toContain("package-flutter-windows.ps1")
	})

	it("provides a manual proof workflow on trusted main without publishing", async () => {
		const workflow = await readFile(proofWorkflowPath, "utf8")

		expect(workflow).toContain("workflow_dispatch:")
		expect(workflow).toContain("ref: main")
		expect(workflow).not.toContain("-SignWindowsBundle")
		expect(workflow).not.toContain("-RequireWindowsSignature")
		expect(workflow).not.toContain("SIGNING_CERTIFICATE")
		expect(workflow).toContain("package-flutter-windows.ps1")
		expect(workflow).toContain("actions/upload-artifact@v7")
		expect(workflow).not.toContain("gh release upload")
		expect(parse(workflow).jobs["windows-proof"].environment).toBe("release")
	})
})


describe("Manual release policy", () => {
  it("requires a trusted exact-commit proof or successful fresh CI before preparing a release", async () => {
    const release = parse(await readFile(workflowPath, "utf8"))
    expect(release.jobs.plan.permissions.actions).toBe("read")
    const proof = release.jobs.plan.steps.find(step => step.id === "ci")
    expect(proof.env.PLANNED_COMMIT).toBe("${{ steps.plan.outputs.commit }}")
    expect(proof.run).toContain("tools/release/ci-proof.mjs")
    expect(release.jobs.validate.if).toContain("needs.plan.outputs.ci_reuse != 'true'")
    expect(release.jobs.prepare.if).toContain("always()")
    expect(release.jobs.prepare.if).toContain("needs.plan.result == 'success'")
    expect(release.jobs.prepare.if).toContain("(needs.plan.outputs.ci_reuse == 'true' || needs.validate.result == 'success')")
  })
  it("packages after reused CI skips validation, but never after failed preparation or dry runs", async () => {
    const release = parse(await readFile(workflowPath, "utf8"))
    const condition = release.jobs["package-windows"].if
    // GitHub implicitly applies success() to job conditions without a status
    // function; a skipped transitive dependency then skips packaging as well.
    const hasStatusFunction = /\b(always|success|failure|cancelled)\s*\(/.test(condition)
    for (const [validation, preparation, dryRun, publish, expected] of [
      ["skipped", "success", false, "true", true],
      ["success", "success", false, "true", true],
      ["success", "failure", false, "true", false],
      ["skipped", "cancelled", false, "true", false],
      ["skipped", "skipped", false, "true", false],
      ["success", "success", true, "true", false],
      ["success", "success", false, "false", false],
    ]) {
      const needs = { plan: { result: "success", outputs: { publish } }, prepare: { result: preparation } }
      const implicitSuccess = [validation, preparation].every(result => result === "success")
      const evaluate = new Function("needs", "inputs", "always", `return (${condition})`)
      const runnable = (hasStatusFunction || implicitSuccess) && evaluate(needs, { dry_run: dryRun }, () => true)
      expect(runnable, `validate=${validation}, prepare=${preparation}, dryRun=${dryRun}, publish=${publish}`).toBe(expected)
    }
  })
  it("separates production startup from integration and requires both Windows gates", async () => {
    const ci = parse(await readFile(resolve(repositoryRoot, ".github/workflows/ci.yml"), "utf8"))
    const steps = ci.jobs["windows-build"].steps
    const build = steps.findIndex(step => step.name === "Build Flutter Windows debug and release")
    const startup = steps.findIndex(step => step.name === "Smoke Flutter Windows startup")
    expect(build).toBeGreaterThan(-1)
    expect(startup).toBeGreaterThan(build)
    expect(steps[startup].run).toContain("-Configuration Debug")
    expect(steps.some(step => step.name === "Run Flutter integration gate")).toBe(false)
    const updateSmoke = steps.find(step => step.name === "Smoke Flutter Windows updater classification")
    expect(updateSmoke.run).toContain("-Configuration Release -Scenario updates")

    expect(ci.jobs["test-windows"].needs.sort()).toEqual(["windows-build", "windows-integration"])
    expect(ci.jobs["test-windows"].if).toContain("always()")
    const gate = ci.jobs["test-windows"].steps[0]
    expect(gate.env.BUILD_RESULT).toContain("needs.windows-build.result")
    expect(gate.env.INTEGRATION_RESULT).toContain("needs.windows-integration.result")
    expect(gate.run).toContain('test "$BUILD_RESULT" = success && test "$INTEGRATION_RESULT" = success')
    const integrationSteps = ci.jobs["windows-integration"].steps
    expect(integrationSteps.find(step => step.name === "Run Flutter integration gate").run).toContain("-CaptureDirectory")
    expect(integrationSteps.map(step => step.run ?? "").join("\n")).not.toContain("capture-flutter-visual.ps1")
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
    expect(workflow.jobs.plan.permissions.contents).toBe("read")
    expect(workflow.jobs.plan.steps.some(step => step.name === "Verify existing GitHub release for backfill")).toBe(false)
    const recovery = workflow.jobs.prepare.steps.find(step => step.name === "Verify existing GitHub release for backfill")
    expect(workflow.jobs.prepare.environment).toBe("release")
    expect(workflow.jobs.prepare.permissions.contents).toBe("write")
    expect(recovery.env.RELEASE_TAG).toBe("${{ needs.plan.outputs.tag }}")
    expect(recovery.env.GH_REPO).toBe("${{ github.repository }}")
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
    expect(Object.keys(ci.jobs).sort()).toEqual(["release-dry-run", "scripts-ubuntu", "test-windows", "windows-build", "windows-integration"])
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
