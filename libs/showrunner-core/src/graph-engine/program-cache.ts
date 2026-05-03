import type { AutomationData } from "showrunner-schema"
import { GraphCompiler, type Program } from "./compiler"

const MAX_CACHE_ENTRIES = 128

interface CachedProgram {
	signature: string
	program: Program
}

const programCache = new Map<string, CachedProgram>()

export function compileAutomationProgram(automation: Pick<AutomationData, "graph" | "subgraphs" | "dataWires">): Program {
	const signature = getAutomationProgramSignature(automation)
	const cached = programCache.get(signature)
	if (cached) return cached.program

	const program = new GraphCompiler().compile(automation.graph, automation.subgraphs, automation.dataWires)
	programCache.set(signature, { signature, program })
	trimProgramCache()
	return program
}

export function validateAutomationProgram(automation: Pick<AutomationData, "graph" | "subgraphs" | "dataWires">) {
	compileAutomationProgram(automation)
}

export function clearAutomationProgramCache() {
	programCache.clear()
}

function getAutomationProgramSignature(automation: Pick<AutomationData, "graph" | "subgraphs" | "dataWires">) {
	return JSON.stringify({
		graph: automation.graph,
		subgraphs: automation.subgraphs ?? [],
		dataWires: automation.dataWires ?? [],
	})
}

function trimProgramCache() {
	while (programCache.size > MAX_CACHE_ENTRIES) {
		const firstKey = programCache.keys().next().value
		if (!firstKey) return
		programCache.delete(firstKey)
	}
}
