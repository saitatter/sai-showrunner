import { nanoid } from "nanoid"
import type { ComputedRef, Ref } from "vue"
import type { AutomationGraph } from "showrunner-schema"
import type { NodePosition } from "./useNodeCanvas"

interface PendingFlowConnection {
	fromNode: string
	fromPort?: string
	canvasPoint: NodePosition
}

interface UseSubgraphCallNodesOptions {
	activeGraph: ComputedRef<AutomationGraph | undefined>
	focusedSubgraphId: Ref<string | undefined>
	pendingFlowConnection: Ref<PendingFlowConnection | null>
	getContextMenuCanvasPoint: () => NodePosition | undefined
	ensureGraph: () => AutomationGraph
	connectFlowToNode: (fromNode: string, fromPort: string | undefined, toNode: string) => void
	openSubgraphCanvas: (subgraphId: string) => void
	closeContextMenu: () => void
	commitUndo: () => void
}

export function useSubgraphCallNodes(options: UseSubgraphCallNodesOptions) {
	const {
		activeGraph,
		focusedSubgraphId,
		pendingFlowConnection,
		getContextMenuCanvasPoint,
		ensureGraph,
		connectFlowToNode,
		openSubgraphCanvas,
		closeContextMenu,
		commitUndo,
	} = options

	function addSubgraphCallNode(subgraphId: string) {
		const graph = ensureGraph()
		const canvasPoint = getContextMenuCanvasPoint() ?? { x: 100, y: 200 }
		const id = nanoid()
		graph.nodes.push({
			id,
			type: "subgraphCall",
			x: canvasPoint.x,
			y: canvasPoint.y,
			subgraphId,
			inputs: {},
		})
		if (pendingFlowConnection.value) {
			connectFlowToNode(pendingFlowConnection.value.fromNode, pendingFlowConnection.value.fromPort, id)
		} else if (!graph.entryNodeId) {
			graph.entryNodeId = id
		}
		focusedSubgraphId.value = subgraphId
		closeContextMenu()
		commitUndo()
	}

	function openSubgraphFromNode(nodeId: string) {
		const graphNode = activeGraph.value?.nodes.find((node) => node.id === nodeId)
		if (graphNode?.type !== "subgraphCall") return
		openSubgraphCanvas(graphNode.subgraphId)
	}

	return {
		addSubgraphCallNode,
		openSubgraphFromNode,
	}
}
