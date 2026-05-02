import { createRequire } from "node:module"

import { describe, expect, it } from "vitest"

const require = createRequire(import.meta.url)
const { createExpandedContext, expandSquashCommits } = require("./expand-squash-commits.cjs")

describe("expandSquashCommits", () => {
	it("expands conventional bullet commits from the squash body", () => {
		const commits = [
			{
				subject: "feat(overlays): refine overlay studio controls (#35)",
				message: [
					"feat(overlays): refine overlay studio controls (#35)",
					"",
					"* feat(overlays): add snap resize controls",
					"* feat(overlays): preview state bindings",
					"* fix(platforms): harden connector ingestion",
				].join("\n"),
				hash: "abc123",
			},
		]

		const expanded = expandSquashCommits(commits)

		expect(expanded.map((commit) => commit.header)).toEqual([
			"feat(overlays): add snap resize controls",
			"feat(overlays): preview state bindings",
			"fix(platforms): harden connector ingestion",
		])
		expect(expanded[0].hash).toBe("abc123")
		expect(expanded[0]).toMatchObject({
			type: "feat",
			scope: "overlays",
			subject: "add snap resize controls",
		})
	})

	it("does not duplicate the squash subject when it also appears in the body", () => {
		const commits = [
			{
				subject: "feat(twitch): sync platform events to overlay state",
				message: [
					"feat(twitch): sync platform events to overlay state",
					"",
					"* feat(twitch): sync platform events to overlay state",
					"* feat(youtube): ingest live chat messages",
				].join("\n"),
				hash: "def456",
			},
		]

		const expanded = expandSquashCommits(commits)

		expect(expanded.map((commit) => commit.header)).toEqual([
			"feat(twitch): sync platform events to overlay state",
			"feat(youtube): ingest live chat messages",
		])
	})
})

describe("createExpandedContext", () => {
	it("returns a cloned context with expanded commits", async () => {
		const logger = {
			log() {},
			warn() {},
		}
		const context = {
			commits: [
				{
					subject: "feat(app): add release updater (#12)",
					message: "feat(app): add release updater (#12)\n\n* feat(app): show latest release\n* fix(app): handle missing assets",
					hash: "789abc",
				},
			],
			options: {
				repositoryUrl: "https://github.com/saitatter/sai-showrunner.git",
			},
			env: {},
			logger,
		}

		const expanded = await createExpandedContext(context)

		expect(expanded).not.toBe(context)
		expect(expanded.commits.map((commit) => commit.header)).toEqual([
			"feat(app): show latest release",
			"fix(app): handle missing assets",
		])
		expect(context.commits).toHaveLength(1)
	})
})
