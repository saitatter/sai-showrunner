import { AutomationDataWire, AutomationGraph, SubgraphDefinition } from "./graph"

export interface AutomationVariableNode {
	id: string
	name: string
	type: "string" | "number" | "boolean" | "color"
	value: string | number | boolean
	x: number
	y: number
}

export interface AutomationData {
	schemaVersion: 2
	graph: AutomationGraph
	subgraphs: SubgraphDefinition[]
	dataWires: AutomationDataWire[]
	variableNodes: AutomationVariableNode[]
	testContext?: any
}

export interface InlineAutomation extends AutomationData {
	queue?: string
	description?: string
}

export function createInlineAutomation(): InlineAutomation {
	return {
		schemaVersion: 2,
		graph: { nodes: [], edges: [], entryNodeId: "" },
		subgraphs: [],
		dataWires: [],
		variableNodes: [],
		queue: undefined,
	}
}

export interface AutomationConfig extends AutomationData {
	name: string
}
