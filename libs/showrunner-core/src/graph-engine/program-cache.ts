import type { AutomationData } from "showrunner-schema"
import { GraphCompiler, type Program } from "./compiler"

const MAX_CACHE_ENTRIES = 128

interface CachedProgram {
	signature: string
	program: Program
}

export interface CompileAutomationProgramOptions {
	entryNodeId?: string
}

const programCache = new Map<string, CachedProgram>()

export function compileAutomationProgram(
	automation: Pick<AutomationData, "graph" | "subgraphs" | "dataWires" | "triggerNodes">,
	options: CompileAutomationProgramOptions = {}
): Program {
	const signature = getAutomationProgramSignature(automation, options)
	const cached = programCache.get(signature)
	if (cached) return cached.program

	const program = new GraphCompiler().compile(
		automation.graph,
		automation.subgraphs,
		automation.dataWires,
		automation.triggerNodes,
		options.entryNodeId
	)
	programCache.set(signature, { signature, program })
	trimProgramCache()
	return program
}

export function validateAutomationProgram(
	automation: Pick<AutomationData, "graph" | "subgraphs" | "dataWires" | "triggerNodes">,
	options: CompileAutomationProgramOptions = {}
) {
	compileAutomationProgram(automation, options)
}

export function clearAutomationProgramCache() {
	programCache.clear()
}

function getAutomationProgramSignature(
	automation: Pick<AutomationData, "graph" | "subgraphs" | "dataWires" | "triggerNodes">,
	options: CompileAutomationProgramOptions
) {
	return JSON.stringify({
		graph: automation.graph,
		subgraphs: automation.subgraphs ?? [],
		dataWires: automation.dataWires ?? [],
		triggerNodes: automation.triggerNodes ?? [],
		entryNodeId: options.entryNodeId ?? automation.graph.entryNodeId,
	})
}

function trimProgramCache() {
	while (programCache.size > MAX_CACHE_ENTRIES) {
		const firstKey = programCache.keys().next().value
		if (!firstKey) return
		programCache.delete(firstKey)
	}
}
