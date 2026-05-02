import { computed, ref, type ComputedRef, type Ref } from "vue"

/**
 * A data-flow connection between an output port of one node and an input port of another.
 * Stored alongside the automation view metadata.
 */
export interface DataWire {
	id: string
	fromNode: string
	fromPort: string
	toNode: string
	toPort: string
}

/** Ephemeral state while dragging a wire from a port */
export interface WireDragState {
	fromNode: string
	fromPort: string
	fromKind: "in" | "out"
	fromX: number
	fromY: number
	currentX: number
	currentY: number
}

export interface PortAddress {
	nodeId: string
	portKey: string
	kind: "in" | "out"
}

export interface PortDef {
	key: string
	label: string
	type: string
}

export interface PortNodeInfo {
	id: string
	x: number
	y: number
	height: number
	width?: number
	inputPorts?: PortDef[]
	outputPorts?: PortDef[]
	configLines?: { label: string; value: string }[]
}

const NODE_WIDTH = 220
const NODE_BASE_HEIGHT = 74
const CONFIG_LINE_HEIGHT = 20
const PORT_LINE_HEIGHT = 18

/** Get the canvas-space position of a port dot */
export function getPortPosition(
	node: PortNodeInfo,
	portKey: string,
	kind: "in" | "out"
): { x: number; y: number } | undefined {
	const ports = kind === "in" ? node.inputPorts : node.outputPorts
	if (!ports) return undefined
	const idx = ports.findIndex((p) => p.key === portKey)
	if (idx < 0) return undefined

	// Vertical offset: after header (icon/title) + config lines
	const configHeight = (node.configLines?.length ?? 0) > 0 ? (node.configLines!.length * CONFIG_LINE_HEIGHT + 4) : 0
	const portsStartY = NODE_BASE_HEIGHT + configHeight + 8
	const portY = node.y + portsStartY + idx * PORT_LINE_HEIGHT + PORT_LINE_HEIGHT / 2

	if (kind === "in") {
		return { x: node.x, y: portY }
	} else {
		return { x: node.x + (node.width ?? NODE_WIDTH), y: portY }
	}
}

/** Check if two port types are compatible for connection */
export function areTypesCompatible(fromType: string, toType: string): boolean {
	if (fromType === toType) return true
	if (fromType === "any" || toType === "any") return true
	// Numeric promotions
	if (fromType === "num" && toType === "str") return true
	if (fromType === "bool" && toType === "str") return true
	if (fromType === "bool" && toType === "num") return true
	return false
}

/** Color for port type (used for wire coloring) */
export function portTypeColor(type: string): string {
	switch (type) {
		case "str": return "#81c784"
		case "num": return "#4fc3f7"
		case "bool": return "#ffb74d"
		case "obj": return "#ce93d8"
		case "list": return "#a1887f"
		case "color": return "#f06292"
		case "vec2": return "#7986cb"
		case "vec3": return "#4dd0e1"
		case "vec4": return "#9575cd"
		case "tex": return "#ff8a65"
		default: return "#999"
	}
}

export function usePortConnections(
	nodes: ComputedRef<PortNodeInfo[]>,
	dataWires: Ref<DataWire[]>,
	zoom: Ref<number>,
	pan: Ref<{ x: number; y: number }>,
	canvasRef: Ref<HTMLElement | undefined>,
	commitUndo: () => void
) {
	const wireDrag = ref<WireDragState | null>(null)

	/** Computed: wire paths for rendering */
	const dataWirePaths = computed(() => {
		const byId = new Map(nodes.value.map((n) => [n.id, n]))
		return dataWires.value.flatMap((wire) => {
			const fromNode = byId.get(wire.fromNode)
			const toNode = byId.get(wire.toNode)
			if (!fromNode || !toNode) return []
			const start = getPortPosition(fromNode, wire.fromPort, "out")
			const end = getPortPosition(toNode, wire.toPort, "in")
			if (!start || !end) return []
			const color = portTypeColor(
				fromNode.outputPorts?.find((p) => p.key === wire.fromPort)?.type ?? "any"
			)
			return [{
				id: wire.id,
				path: bezierPath(start.x, start.y, end.x, end.y),
				color,
				fromNode: wire.fromNode,
				fromPort: wire.fromPort,
				toNode: wire.toNode,
				toPort: wire.toPort,
			}]
		})
	})

	/** The in-progress wire path while dragging */
	const dragWirePath = computed(() => {
		const drag = wireDrag.value
		if (!drag) return null
		const isFromOutput = drag.fromKind === "out"
		const startX = drag.fromX
		const startY = drag.fromY
		const endX = drag.currentX
		const endY = drag.currentY
		return {
			path: isFromOutput
				? bezierPath(startX, startY, endX, endY)
				: bezierPath(endX, endY, startX, startY),
			color: "#fff8",
		}
	})

	function startWireDrag(nodeId: string, portKey: string, kind: "in" | "out", event: PointerEvent) {
		event.stopPropagation()
		event.preventDefault()
		const node = nodes.value.find((n) => n.id === nodeId)
		if (!node) return
		const pos = getPortPosition(node, portKey, kind)
		if (!pos) return

		// If dragging from an input that already has a wire, disconnect and start dragging from the other end
		if (kind === "in") {
			const existingIdx = dataWires.value.findIndex((w) => w.toNode === nodeId && w.toPort === portKey)
			if (existingIdx >= 0) {
				const existing = dataWires.value[existingIdx]
				const fromNode = nodes.value.find((n) => n.id === existing.fromNode)
				const fromPos = fromNode ? getPortPosition(fromNode, existing.fromPort, "out") : undefined
				dataWires.value.splice(existingIdx, 1)
				if (fromPos && fromNode) {
					wireDrag.value = {
						fromNode: existing.fromNode,
						fromPort: existing.fromPort,
						fromKind: "out",
						fromX: fromPos.x,
						fromY: fromPos.y,
						currentX: pos.x,
						currentY: pos.y,
					}
					setupDragListeners()
					return
				}
			}
		}

		wireDrag.value = {
			fromNode: nodeId,
			fromPort: portKey,
			fromKind: kind,
			fromX: pos.x,
			fromY: pos.y,
			currentX: pos.x,
			currentY: pos.y,
		}
		setupDragListeners()
	}

	function setupDragListeners() {
		window.addEventListener("pointermove", onDragMove)
		window.addEventListener("pointerup", onDragEnd)
	}

	function onDragMove(event: PointerEvent) {
		if (!wireDrag.value || !canvasRef.value) return
		const surface = canvasRef.value.querySelector<HTMLElement>(".node-automation__surface")
		if (!surface) return
		const rect = surface.getBoundingClientRect()
		wireDrag.value.currentX = (event.clientX - rect.left) / zoom.value
		wireDrag.value.currentY = (event.clientY - rect.top) / zoom.value
	}

	function onDragEnd(event: PointerEvent) {
		window.removeEventListener("pointermove", onDragMove)
		window.removeEventListener("pointerup", onDragEnd)

		const drag = wireDrag.value
		if (!drag) return

		// Find the port under the cursor
		const target = findPortUnderCursor(event, drag)
		if (target) {
			const fromNode = drag.fromKind === "out" ? drag.fromNode : target.nodeId
			const fromPort = drag.fromKind === "out" ? drag.fromPort : target.portKey
			const toNode = drag.fromKind === "out" ? target.nodeId : drag.fromNode
			const toPort = drag.fromKind === "out" ? target.portKey : drag.fromPort

			// Don't connect a node to itself
			if (fromNode !== toNode && !wouldCreateCycle(fromNode, toNode)) {
				// Remove existing wire to this input (one wire per input port)
				const existingIdx = dataWires.value.findIndex((w) => w.toNode === toNode && w.toPort === toPort)
				if (existingIdx >= 0) dataWires.value.splice(existingIdx, 1)

				dataWires.value.push({
					id: `${fromNode}:${fromPort}->${toNode}:${toPort}`,
					fromNode,
					fromPort,
					toNode,
					toPort,
				})
				commitUndo()
			}
		}

		wireDrag.value = null
	}

	/** Check if adding an edge fromNode→toNode would create a cycle in the data wire graph */
	function wouldCreateCycle(fromNode: string, toNode: string): boolean {
		// Walk forward from toNode through existing wires; if we reach fromNode, it's a cycle
		const visited = new Set<string>()
		const stack = [toNode]
		while (stack.length > 0) {
			const current = stack.pop()!
			if (current === fromNode) return true
			if (visited.has(current)) continue
			visited.add(current)
			for (const wire of dataWires.value) {
				if (wire.fromNode === current) {
					stack.push(wire.toNode)
				}
			}
		}
		return false
	}

	function findPortUnderCursor(event: PointerEvent, drag: WireDragState): PortAddress | undefined {
		const targetKind = drag.fromKind === "out" ? "in" : "out"
		const SNAP_RADIUS = 18 / zoom.value

		for (const node of nodes.value) {
			if (node.id === drag.fromNode && targetKind === drag.fromKind) continue
			const ports = targetKind === "in" ? node.inputPorts : node.outputPorts
			if (!ports) continue
			for (const port of ports) {
				const pos = getPortPosition(node, port.key, targetKind)
				if (!pos) continue
				const dx = pos.x - drag.currentX
				const dy = pos.y - drag.currentY
				if (Math.sqrt(dx * dx + dy * dy) < SNAP_RADIUS) {
					// Type compatibility check
					const fromPorts = drag.fromKind === "out"
						? nodes.value.find((n) => n.id === drag.fromNode)?.outputPorts
						: nodes.value.find((n) => n.id === drag.fromNode)?.inputPorts
					const fromPortDef = fromPorts?.find((p) => p.key === drag.fromPort)
					if (fromPortDef && areTypesCompatible(
						drag.fromKind === "out" ? fromPortDef.type : port.type,
						drag.fromKind === "out" ? port.type : fromPortDef.type
					)) {
						return { nodeId: node.id, portKey: port.key, kind: targetKind }
					}
				}
			}
		}
		return undefined
	}

	function deleteDataWire(wireId: string) {
		const idx = dataWires.value.findIndex((w) => w.id === wireId)
		if (idx >= 0) {
			dataWires.value.splice(idx, 1)
			commitUndo()
		}
	}

	return {
		wireDrag,
		dataWirePaths,
		dragWirePath,
		startWireDrag,
		deleteDataWire,
	}
}

function bezierPath(x1: number, y1: number, x2: number, y2: number): string {
	const dx = Math.abs(x2 - x1)
	const cp = Math.max(60, dx * 0.4)
	return `M ${x1} ${y1} C ${x1 + cp} ${y1}, ${x2 - cp} ${y2}, ${x2} ${y2}`
}
