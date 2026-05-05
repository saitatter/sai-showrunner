import { computed, nextTick, onMounted, onUnmounted, ref, watch, type ComputedRef, type Ref } from "vue"
import {
	collectRenderedGraphPortPositions,
	findNearestGraphPort,
	graphBezierPath,
	graphPointFromClient,
	graphPortPositionKey,
	graphWireId,
	oppositeGraphPortKind,
	resolveGraphWireEndpoints,
	type GraphPortCandidate,
	type GraphPoint,
} from "showrunner-ui-core/src/util/graph"

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

export interface DataWireValidation {
	valid: boolean
	message?: string
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
	fromType = normalizePortType(fromType)
	toType = normalizePortType(toType)
	if (fromType === toType) return true
	if (fromType === "any" || toType === "any") return true
	return false
}

export function wouldCreateDataWireCycle(wires: DataWire[], fromNode: string, toNode: string): boolean {
	const visited = new Set<string>()
	const stack = [toNode]
	while (stack.length > 0) {
		const current = stack.pop()!
		if (current === fromNode) return true
		if (visited.has(current)) continue
		visited.add(current)
		for (const wire of wires) {
			if (wire.fromNode === current) {
				stack.push(wire.toNode)
			}
		}
	}
	return false
}

function normalizePortType(type: string): string {
	const normalized = String(type || "any").trim().toLowerCase()
	switch (normalized) {
		case "string":
		case "str":
			return "str"
		case "number":
		case "num":
			return "num"
		case "boolean":
		case "bool":
			return "bool"
		case "object":
		case "obj":
			return "obj"
		case "array":
		case "list":
			return "list"
		default:
			return normalized || "any"
	}
}

/** Color for port type (used for wire coloring) */
export function portTypeColor(type: string): string {
	switch (normalizePortType(type)) {
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
	const layoutVersion = ref(0)
	/** Wire that was disconnected at drag start (for restoring on cancel) */
	let disconnectedWire: DataWire | null = null
	let layoutFrame: number | undefined
	let resizeObserver: ResizeObserver | undefined

	function scheduleLayoutRefresh() {
		if (layoutFrame != null) cancelAnimationFrame(layoutFrame)
		nextTick(() => {
			layoutFrame = requestAnimationFrame(() => {
				layoutVersion.value += 1
				layoutFrame = undefined
			})
		})
	}

	onMounted(() => {
		scheduleLayoutRefresh()
		const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
		if (surface && typeof ResizeObserver !== "undefined") {
			resizeObserver = new ResizeObserver(scheduleLayoutRefresh)
			resizeObserver.observe(surface)
		}
	})

	onUnmounted(() => {
		if (layoutFrame != null) cancelAnimationFrame(layoutFrame)
		resizeObserver?.disconnect()
	})

	watch(nodes, scheduleLayoutRefresh, { deep: true, flush: "post" })
	watch(dataWires, scheduleLayoutRefresh, { deep: true, flush: "post" })

	const renderedPortPositions = computed(() => {
		layoutVersion.value
		const surface = canvasRef.value?.querySelector<HTMLElement>(".node-automation__surface")
		const positions = new Map<string, GraphPoint>()
		if (!surface) return positions

		return collectRenderedGraphPortPositions(surface, zoom.value, {
			selector: "[data-port-node-id]",
			nodeIdDatasetKey: "portNodeId",
			portKeyDatasetKey: "portKey",
			kindDatasetKey: "portKind",
		})
	})

	/** Computed: wire paths for rendering */
	const dataWirePaths = computed(() => {
		const byId = new Map(nodes.value.map((n) => [n.id, n]))
		const portPositions = renderedPortPositions.value
		return dataWires.value.flatMap((wire) => {
			const fromNode = byId.get(wire.fromNode)
			const toNode = byId.get(wire.toNode)
			if (!fromNode || !toNode) return []
			const start =
				getRenderedPortPosition(portPositions, wire.fromNode, wire.fromPort, "out") ?? getPortPosition(fromNode, wire.fromPort, "out")
			const end = getRenderedPortPosition(portPositions, wire.toNode, wire.toPort, "in") ?? getPortPosition(toNode, wire.toPort, "in")
			if (!start || !end) return []
			const fromPort = fromNode.outputPorts?.find((p) => p.key === wire.fromPort)
			const toPort = toNode.inputPorts?.find((p) => p.key === wire.toPort)
			const sourceType = fromPort?.type ?? "any"
			const validation = validateResolvedWire(fromPort, toPort)
			return [{
				id: wire.id,
				path: graphBezierPath(start.x, start.y, end.x, end.y),
				color: validation.valid ? portTypeColor(sourceType) : "#ef5350",
				fromNode: wire.fromNode,
				fromPort: wire.fromPort,
				toNode: wire.toNode,
				toPort: wire.toPort,
				valid: validation.valid,
				validationMessage: validation.message,
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
		const target = findNearestPortForDrag(drag)
		const validation = target ? validateDragTarget(drag, target) : { valid: true }
		return {
			path: isFromOutput
				? graphBezierPath(startX, startY, endX, endY)
				: graphBezierPath(endX, endY, startX, startY),
			color: validation.valid ? "#fff8" : "#ef5350",
			valid: validation.valid,
			validationMessage: validation.message,
		}
	})
	const dragPortPreview = computed(() => {
		const drag = wireDrag.value
		if (!drag) return undefined
		const target = findNearestPortForDrag(drag)
		if (!target) return undefined
		return {
			...target,
			...validateDragTarget(drag, target),
		}
	})

	function startWireDrag(nodeId: string, portKey: string, kind: "in" | "out", event: PointerEvent) {
		event.stopPropagation()
		event.preventDefault()
		const node = nodes.value.find((n) => n.id === nodeId)
		if (!node) return
		const portPositions = renderedPortPositions.value
		const pos = getRenderedPortPosition(portPositions, nodeId, portKey, kind) ?? getPortPosition(node, portKey, kind)
		if (!pos) return

		disconnectedWire = null

		// If dragging from an input that already has a wire, disconnect and start dragging from the other end
		if (kind === "in") {
			const existingIdx = dataWires.value.findIndex((w) => w.toNode === nodeId && w.toPort === portKey)
			if (existingIdx >= 0) {
				const existing = dataWires.value[existingIdx]
				const fromNode = nodes.value.find((n) => n.id === existing.fromNode)
				const fromPos = fromNode
					? getRenderedPortPosition(portPositions, existing.fromNode, existing.fromPort, "out") ??
						getPortPosition(fromNode, existing.fromPort, "out")
					: undefined
				disconnectedWire = { ...existing }
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
		updateDragPoint(event)

		// Find the port under the cursor
		const target = findPortUnderCursor(event, drag)
		let connected = false
		if (target) {
			const endpoints = resolveGraphWireEndpoints(drag, target)
			const validation = validateDragTarget(drag, target)

			if (validation.valid) {
				// Remove existing wire to this input (one wire per input port)
				const existingIdx = dataWires.value.findIndex((w) => w.toNode === endpoints.toNode && w.toPort === endpoints.toPort)
				if (existingIdx >= 0) dataWires.value.splice(existingIdx, 1)

				dataWires.value.push({
					id: graphWireId(endpoints),
					...endpoints,
				})
				connected = true
				commitUndo()
			}
		}

		// If drag was cancelled (dropped on empty space) and we disconnected a wire, restore it
		if (!connected && disconnectedWire) {
			dataWires.value.push(disconnectedWire)
		}
		disconnectedWire = null
		wireDrag.value = null
	}

	function wouldCreateCycle(fromNode: string, toNode: string): boolean {
		return wouldCreateDataWireCycle(dataWires.value, fromNode, toNode)
	}

	function findPortUnderCursor(event: PointerEvent, drag: WireDragState): PortAddress | undefined {
		const targetKind = oppositeGraphPortKind(drag.fromKind)
		const elementTarget = findPortFromEventTarget(event, targetKind)
		if (elementTarget && isCompatibleTarget(drag, elementTarget)) {
			return elementTarget
		}

		return findNearestPortForDrag(drag)
	}

	function findNearestPortForDrag(drag: WireDragState): PortAddress | undefined {
		const targetKind = oppositeGraphPortKind(drag.fromKind)
		const SNAP_RADIUS = 34 / zoom.value
		const nearest = findNearestGraphPort(
			{ x: drag.currentX, y: drag.currentY },
			getPortCandidates(targetKind),
			SNAP_RADIUS,
			(candidate) => isCompatibleTarget(drag, candidate)
		)
		return nearest ? { nodeId: nearest.nodeId, portKey: nearest.portKey, kind: nearest.kind } : undefined
	}

	function getPortCandidates(targetKind: "in" | "out"): GraphPortCandidate[] {
		const candidates: GraphPortCandidate[] = []
		const portPositions = renderedPortPositions.value
		for (const node of nodes.value) {
			const ports = targetKind === "in" ? node.inputPorts : node.outputPorts
			if (!ports) continue
			for (const port of ports) {
				const position = getRenderedPortPosition(portPositions, node.id, port.key, targetKind) ?? getPortPosition(node, port.key, targetKind)
				if (!position) continue
				candidates.push({ nodeId: node.id, portKey: port.key, kind: targetKind, position })
			}
		}
		return candidates
	}

	function updateDragPoint(event: PointerEvent) {
		if (!wireDrag.value || !canvasRef.value) return
		const surface = canvasRef.value.querySelector<HTMLElement>(".node-automation__surface")
		if (!surface) return
		const point = graphPointFromClient(surface, event.clientX, event.clientY, zoom.value)
		wireDrag.value.currentX = point.x
		wireDrag.value.currentY = point.y
	}

	function findPortFromEventTarget(event: PointerEvent, expectedKind: "in" | "out"): PortAddress | undefined {
		const element = (event.target as HTMLElement | null)?.closest<HTMLElement>("[data-port-node-id]")
		if (!element) return undefined
		const nodeId = element.dataset.portNodeId
		const portKey = element.dataset.portKey
		const kind = element.dataset.portKind
		if (!nodeId || !portKey || kind !== expectedKind) return undefined
		return { nodeId, portKey, kind: expectedKind }
	}

	function getRenderedPortPosition(positions: Map<string, GraphPoint>, nodeId: string, portKey: string, kind: "in" | "out") {
		return positions.get(graphPortPositionKey(nodeId, portKey, kind))
	}

	function getPortDef(address: PortAddress) {
		const node = nodes.value.find((n) => n.id === address.nodeId)
		const ports = address.kind === "out" ? node?.outputPorts : node?.inputPorts
		return ports?.find((p) => p.key === address.portKey)
	}

	function isCompatibleTarget(drag: WireDragState, target: PortAddress): boolean {
		return validateDragTarget(drag, target).valid
	}

	function validateDragTarget(drag: WireDragState, target: PortAddress): DataWireValidation {
		const fromAddress: PortAddress = { nodeId: drag.fromNode, portKey: drag.fromPort, kind: drag.fromKind }
		const fromPortDef = getPortDef(fromAddress)
		const targetPortDef = getPortDef(target)
		if (target.nodeId === drag.fromNode) {
			return { valid: false, message: "Data wires cannot connect a node to itself." }
		}
		if (!fromPortDef || !targetPortDef) return { valid: false, message: "Missing source or target port." }
		const sourceType = drag.fromKind === "out" ? fromPortDef.type : targetPortDef.type
		const destinationType = drag.fromKind === "out" ? targetPortDef.type : fromPortDef.type
		if (!areTypesCompatible(sourceType, destinationType)) {
			return { valid: false, message: `Incompatible wire: ${sourceType} -> ${destinationType}` }
		}

		const { fromNode, toNode } = resolveGraphWireEndpoints(drag, target)
		if (wouldCreateCycle(fromNode, toNode)) {
			return { valid: false, message: "Data wire would create a circular dependency." }
		}
		return { valid: true }
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
		dragPortPreview,
		startWireDrag,
		deleteDataWire,
	}
}

function validateResolvedWire(fromPort: PortDef | undefined, toPort: PortDef | undefined): DataWireValidation {
	if (!fromPort) return { valid: false, message: "Missing output port." }
	if (!toPort) return { valid: false, message: "Missing input port." }
	if (!areTypesCompatible(fromPort.type, toPort.type)) {
		return { valid: false, message: `Incompatible wire: ${fromPort.type} -> ${toPort.type}` }
	}
	return { valid: true }
}
