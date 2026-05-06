import { computed, ref, type Ref } from "vue"

export interface GraphPoint {
	x: number
	y: number
}

export interface GraphBounds {
	minX: number
	minY: number
	width: number
	height: number
}

export interface GraphViewportSize {
	width: number
	height: number
}

export type GraphPortKind = "in" | "out"

export interface GraphPortAddress {
	nodeId: string
	portKey: string
	kind: GraphPortKind
}

export interface GraphPortCandidate extends GraphPortAddress {
	position: GraphPoint
}

export interface GraphWireDragAddress {
	fromNode: string
	fromPort: string
	fromKind: GraphPortKind
}

export interface GraphWireEndpoints {
	fromNode: string
	fromPort: string
	toNode: string
	toPort: string
}

export interface GraphValidationResult {
	valid: boolean
	message?: string
	code?: string
}

export type GraphIssueSeverity = "error" | "warning" | "info"

export interface GraphIssue {
	severity: GraphIssueSeverity
	message: string
	nodeId?: string
	portKey?: string
	wireId?: string
	code?: string
}

export interface GraphRunResult<TOutput> {
	output?: TOutput
	issues: GraphIssue[]
}

export interface GraphRuntimeAdapter<TGraph, TOutput> {
	evaluate: (graph: TGraph) => GraphRunResult<TOutput>
}

export interface GraphRuntimeSnapshot<TOutput> {
	output?: TOutput
	lastGoodOutput?: TOutput
	issues: GraphIssue[]
	errorMessages: string[]
	ok: boolean
}

export interface GraphSkinTokens {
	canvasBackground: string
	panelBackground: string
	panelBorder: string
	nodeBackground: string
	nodeBorder: string
	nodeSelected: string
	wireDefault: string
	wireInvalid: string
	textMuted: string
}

export interface GraphFrameLike {
	id: string
	x: number
	y: number
	width: number
	height: number
	nodeIds?: string[]
}

export interface GraphFrameItemLike {
	id: string
	x: number
	y: number
	width: number
	height: number
}

export interface GraphItemBounds {
	x: number
	y: number
	width: number
	height: number
}

export interface GraphPortPositionOptions {
	selector: string
	nodeIdDatasetKey: string
	portKeyDatasetKey: string
	kindDatasetKey: string
	nodeSelector?: string
}

export interface GraphSelectionOptions {
	selectedNodeId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	getNodeIds?: () => Iterable<string>
	onNodeSelectionChange?: () => void
}

export interface GraphDraggableNode extends GraphPoint {
	id: string
}

export interface GraphNodeDragOptions<TNode extends GraphDraggableNode> {
	selectedNodeId: Ref<string | undefined>
	selectedNodeIds: Ref<Set<string>>
	zoom: Ref<number>
	getNodes: () => TNode[]
	setNodePosition: (node: TNode, position: GraphPoint) => void
	selectOnlyNode: (nodeId: string) => void
	toggleNodeSelection: (nodeId: string) => void
	snapCoordinate?: (value: number) => number
	minX?: number
	minY?: number
	onDragMove?: (draggedIds: Set<string>) => void
	onDragEnd?: (draggedIds: Set<string>, moved: boolean) => void
}

export interface GraphHistoryOptions<TSnapshot> {
	clone: (snapshot: TSnapshot) => TSnapshot
	apply: (snapshot: TSnapshot) => void
	historyKey?: (snapshot: TSnapshot) => string
	limit?: number
}

export interface GraphContextMenuGroupsOptions {
	defaultOpenGroups?: Record<string, boolean>
}

export function graphPortPositionKey(nodeId: string, portKey: string, kind: GraphPortKind) {
	return `${kind}:${nodeId}:${portKey}`
}

export function oppositeGraphPortKind(kind: GraphPortKind): GraphPortKind {
	return kind === "out" ? "in" : "out"
}

export function graphWireId(endpoints: GraphWireEndpoints) {
	return `${endpoints.fromNode}:${endpoints.fromPort}->${endpoints.toNode}:${endpoints.toPort}`
}

export function resolveGraphWireEndpoints(drag: GraphWireDragAddress, target: GraphPortAddress): GraphWireEndpoints {
	return {
		fromNode: drag.fromKind === "out" ? drag.fromNode : target.nodeId,
		fromPort: drag.fromKind === "out" ? drag.fromPort : target.portKey,
		toNode: drag.fromKind === "out" ? target.nodeId : drag.fromNode,
		toPort: drag.fromKind === "out" ? target.portKey : drag.fromPort,
	}
}

export function graphDistance(a: GraphPoint, b: GraphPoint) {
	return Math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2)
}

export function clampGraphZoom(value: number, minZoom: number, maxZoom: number) {
	return Math.max(minZoom, Math.min(maxZoom, Number(value.toFixed(2))))
}

export function graphFitZoom(
	bounds: Pick<GraphBounds, "width" | "height">,
	viewport: GraphViewportSize,
	options: { padding?: number; maxZoom?: number; minZoom?: number } = {}
) {
	const padding = options.padding ?? 0
	const availableWidth = Math.max(1, viewport.width - padding)
	const availableHeight = Math.max(1, viewport.height - padding)
	const widthScale = availableWidth / Math.max(1, bounds.width)
	const heightScale = availableHeight / Math.max(1, bounds.height)
	return clampGraphZoom(
		Math.min(widthScale, heightScale, options.maxZoom ?? 1),
		options.minZoom ?? 0,
		options.maxZoom ?? 1
	)
}

export function centerGraphBoundsPan(
	bounds: GraphBounds,
	viewport: GraphViewportSize,
	zoom: number
): GraphPoint {
	return {
		x: (viewport.width - bounds.width * zoom) / 2 - bounds.minX * zoom,
		y: (viewport.height - bounds.height * zoom) / 2 - bounds.minY * zoom,
	}
}

export function graphScrollTargetForBounds(bounds: Pick<GraphBounds, "minX" | "minY">, zoom: number, padding = 0): GraphPoint {
	return {
		x: Math.max(0, bounds.minX * zoom - padding),
		y: Math.max(0, bounds.minY * zoom - padding),
	}
}

export function graphIssuesToMessages(issues: GraphIssue[]) {
	return issues.filter((issue) => issue.severity === "error").map((issue) => issue.message)
}

export function graphIssuesBySeverity(issues: GraphIssue[], severity: GraphIssueSeverity) {
	return issues.filter((issue) => issue.severity === severity)
}

export function graphIssueMessagesBySeverity(issues: GraphIssue[], severity: GraphIssueSeverity) {
	return graphIssuesBySeverity(issues, severity).map((issue) => issue.message)
}

export function graphValidationFromIssues(issues: GraphIssue[]): GraphValidationResult {
	const error = issues.find((issue) => issue.severity === "error")
	return error ? { valid: false, message: error.message, code: error.code } : { valid: true }
}

export function evaluateGraphRuntime<TGraph, TOutput>(
	adapter: GraphRuntimeAdapter<TGraph, TOutput>,
	graph: TGraph,
	previousLastGoodOutput?: TOutput
): GraphRuntimeSnapshot<TOutput> {
	const result = adapter.evaluate(graph)
	const errorMessages = graphIssuesToMessages(result.issues)
	const ok = errorMessages.length === 0
	const lastGoodOutput = ok ? (result.output ?? previousLastGoodOutput) : previousLastGoodOutput
	return {
		output: result.output,
		lastGoodOutput,
		issues: result.issues,
		errorMessages,
		ok,
	}
}

export function graphSkinStyle(tokens: GraphSkinTokens): Record<string, string> {
	return {
		"--graph-canvas-background": tokens.canvasBackground,
		"--graph-panel-background": tokens.panelBackground,
		"--graph-panel-border": tokens.panelBorder,
		"--graph-node-background": tokens.nodeBackground,
		"--graph-node-border": tokens.nodeBorder,
		"--graph-node-selected": tokens.nodeSelected,
		"--graph-wire-default": tokens.wireDefault,
		"--graph-wire-invalid": tokens.wireInvalid,
		"--graph-text-muted": tokens.textMuted,
	}
}

export function getGraphItemBounds(items: Iterable<GraphFrameItemLike>): GraphItemBounds | undefined {
	const boxes = [...items]
	if (!boxes.length) return undefined
	const minX = Math.min(...boxes.map((box) => box.x))
	const minY = Math.min(...boxes.map((box) => box.y))
	const maxX = Math.max(...boxes.map((box) => box.x + box.width))
	const maxY = Math.max(...boxes.map((box) => box.y + box.height))
	return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
}

export function getGraphFrameContainingPoint<TFrame extends GraphFrameLike>(frames: Iterable<TFrame>, point: GraphPoint): TFrame | undefined {
	return [...frames].find((frame) =>
		point.x >= frame.x &&
		point.x <= frame.x + frame.width &&
		point.y >= frame.y &&
		point.y <= frame.y + frame.height
	)
}

export function addGraphFrameMembers(frame: GraphFrameLike, memberIds: Iterable<string>) {
	const next = new Set(frame.nodeIds ?? [])
	const previousSize = next.size
	for (const memberId of memberIds) next.add(memberId)
	frame.nodeIds = [...next]
	return next.size !== previousSize
}

export function moveGraphFrameMembers(frames: Iterable<GraphFrameLike>, memberIds: Iterable<string>, targetFrameId?: string) {
	const ids = new Set(memberIds)
	if (!ids.size) return false
	let changed = false
	let target: GraphFrameLike | undefined

	for (const frame of frames) {
		if (frame.id === targetFrameId) target = frame
		const next = (frame.nodeIds ?? []).filter((memberId) => !ids.has(memberId))
		if (next.length !== (frame.nodeIds ?? []).length) {
			frame.nodeIds = next
			changed = true
		}
	}

	if (target) changed = addGraphFrameMembers(target, ids) || changed
	return changed
}

export function getGraphFrameMinimumSize(
	frame: GraphFrameLike,
	memberBounds: GraphItemBounds | undefined,
	padding = 36,
	minimum = { width: 160, height: 96 }
) {
	if (!memberBounds) return minimum
	return {
		width: Math.max(minimum.width, Math.ceil(memberBounds.x + memberBounds.width - frame.x + padding)),
		height: Math.max(minimum.height, Math.ceil(memberBounds.y + memberBounds.height - frame.y + padding)),
	}
}

export function findNearestGraphPort(
	point: GraphPoint,
	candidates: GraphPortCandidate[],
	snapRadius: number,
	isValidCandidate: (candidate: GraphPortCandidate) => boolean = () => true
): GraphPortCandidate | undefined {
	let nearest: { candidate: GraphPortCandidate; distance: number } | undefined
	for (const candidate of candidates) {
		const distance = graphDistance(candidate.position, point)
		if (distance >= snapRadius || !isValidCandidate(candidate)) continue
		if (!nearest || distance < nearest.distance) {
			nearest = { candidate, distance }
		}
	}
	return nearest?.candidate
}

export function graphBezierPath(
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	options: { minControl?: number; controlRatio?: number; controlScale?: number } = {}
): string {
	const dx = Math.abs(x2 - x1)
	const cp = Math.max(options.minControl ?? 60, dx * (options.controlRatio ?? options.controlScale ?? 0.4))
	return `M ${x1} ${y1} C ${x1 + cp} ${y1}, ${x2 - cp} ${y2}, ${x2} ${y2}`
}

export function graphPointFromClient(surface: HTMLElement, clientX: number, clientY: number, zoom: number): GraphPoint {
	const rect = surface.getBoundingClientRect()
	return {
		x: (clientX - rect.left) / zoom,
		y: (clientY - rect.top) / zoom,
	}
}

export function collectRenderedGraphPortPositions(
	surface: HTMLElement,
	zoom: number,
	options: GraphPortPositionOptions
) {
	const positions = new Map<string, GraphPoint>()
	const surfaceRect = surface.getBoundingClientRect()
	const elements = surface.querySelectorAll<HTMLElement>(options.selector)
	for (const element of elements) {
		const nodeId = element.dataset[options.nodeIdDatasetKey]
		const portKey = element.dataset[options.portKeyDatasetKey]
		const kind = element.dataset[options.kindDatasetKey]
		if (!nodeId || !portKey || (kind !== "in" && kind !== "out")) continue

		const portRect = element.getBoundingClientRect()
		positions.set(graphPortPositionKey(nodeId, portKey, kind), {
			x: (portRect.left + portRect.width / 2 - surfaceRect.left) / zoom,
			y: (portRect.top + portRect.height / 2 - surfaceRect.top) / zoom,
		})
	}
	return positions
}

export function collectRenderedGraphPortOffsets(
	surface: HTMLElement,
	zoom: number,
	options: GraphPortPositionOptions
) {
	const offsets = new Map<string, GraphPoint>()
	const elements = surface.querySelectorAll<HTMLElement>(options.selector)
	for (const element of elements) {
		const nodeId = element.dataset[options.nodeIdDatasetKey]
		const portKey = element.dataset[options.portKeyDatasetKey]
		const kind = element.dataset[options.kindDatasetKey]
		if (!nodeId || !portKey || (kind !== "in" && kind !== "out")) continue

		const nodeElement = element.closest<HTMLElement>(options.nodeSelector ?? "[data-graph-node-id]")
		if (!nodeElement) continue

		const nodeRect = nodeElement.getBoundingClientRect()
		const portRect = element.getBoundingClientRect()
		offsets.set(graphPortPositionKey(nodeId, portKey, kind), {
			x: (portRect.left + portRect.width / 2 - nodeRect.left) / zoom,
			y: (portRect.top + portRect.height / 2 - nodeRect.top) / zoom,
		})
	}
	return offsets
}

export function useGraphSelection(options: GraphSelectionOptions) {
	const { selectedNodeId, selectedNodeIds, getNodeIds, onNodeSelectionChange } = options

	function filterExistingNodeIds(ids: Iterable<string>) {
		if (!getNodeIds) return new Set(ids)
		const existing = new Set(getNodeIds())
		return new Set([...ids].filter((id) => existing.has(id)))
	}

	function commitSelection(next: Set<string>, activeNodeId?: string) {
		selectedNodeIds.value = next
		selectedNodeId.value = activeNodeId && next.has(activeNodeId) ? activeNodeId : [...next][0]
		onNodeSelectionChange?.()
	}

	function isNodeSelected(nodeId: string) {
		return selectedNodeIds.value.has(nodeId)
	}

	function setSelectedNodeIds(ids: Iterable<string>, activeNodeId?: string) {
		commitSelection(filterExistingNodeIds(ids), activeNodeId)
	}

	function selectOnlyNode(nodeId: string) {
		setSelectedNodeIds([nodeId], nodeId)
	}

	function toggleNodeSelection(nodeId: string) {
		const next = filterExistingNodeIds(selectedNodeIds.value)
		const activeNodeId = next.has(nodeId) ? undefined : nodeId
		if (next.has(nodeId)) next.delete(nodeId)
		else next.add(nodeId)
		commitSelection(next, activeNodeId ?? [...next][next.size - 1])
	}

	function clearNodeSelection() {
		commitSelection(new Set())
	}

	return {
		isNodeSelected,
		setSelectedNodeIds,
		selectOnlyNode,
		toggleNodeSelection,
		clearNodeSelection,
	}
}

export function useGraphNodeDrag<TNode extends GraphDraggableNode>(options: GraphNodeDragOptions<TNode>) {
	const {
		selectedNodeId,
		selectedNodeIds,
		zoom,
		getNodes,
		setNodePosition,
		selectOnlyNode,
		toggleNodeSelection,
		snapCoordinate = (value: number) => Math.round(value),
		minX = 0,
		minY = 0,
		onDragMove,
		onDragEnd,
	} = options

	function startNodeDrag(event: PointerEvent, node: TNode) {
		if (event.shiftKey || event.ctrlKey || event.metaKey) toggleNodeSelection(node.id)
		else if (!selectedNodeIds.value.has(node.id)) selectOnlyNode(node.id)
		else selectedNodeId.value = node.id

		const startX = event.clientX
		const startY = event.clientY
		const dragIds = selectedNodeIds.value.has(node.id) ? [...selectedNodeIds.value] : [node.id]
		const initialPositions = new Map<string, GraphPoint>()
		for (const id of dragIds) {
			const item = getNodes().find((candidate) => candidate.id === id)
			if (item) initialPositions.set(id, { x: item.x, y: item.y })
		}

		const target = event.currentTarget as HTMLElement
		target.setPointerCapture(event.pointerId)

		function onMove(moveEvent: PointerEvent) {
			const dx = (moveEvent.clientX - startX) / zoom.value
			const dy = (moveEvent.clientY - startY) / zoom.value
			const nodesById = new Map(getNodes().map((candidate) => [candidate.id, candidate]))
			for (const [id, start] of initialPositions) {
				const item = nodesById.get(id)
				if (!item) continue
				setNodePosition(item, {
					x: Math.max(minX, snapCoordinate(start.x + dx)),
					y: Math.max(minY, snapCoordinate(start.y + dy)),
				})
			}
			onDragMove?.(new Set(dragIds))
		}

		function onUp(upEvent: PointerEvent) {
			if (target.hasPointerCapture(upEvent.pointerId)) target.releasePointerCapture(upEvent.pointerId)
			target.removeEventListener("pointermove", onMove)
			target.removeEventListener("pointerup", onUp)
			target.removeEventListener("pointercancel", onUp)
			const nodesById = new Map(getNodes().map((candidate) => [candidate.id, candidate]))
			const moved = [...initialPositions].some(([id, initial]) => {
				const item = nodesById.get(id)
				return Boolean(item && (item.x !== initial.x || item.y !== initial.y))
			})
			onDragEnd?.(new Set(dragIds), moved)
		}

		target.addEventListener("pointermove", onMove)
		target.addEventListener("pointerup", onUp)
		target.addEventListener("pointercancel", onUp)
	}

	return {
		startNodeDrag,
	}
}

export function useGraphHistory<TSnapshot>(options: GraphHistoryOptions<TSnapshot>) {
	const {
		clone,
		apply,
		historyKey = (snapshot: TSnapshot) => JSON.stringify(snapshot),
		limit = 80,
	} = options

	const undoStack = ref<TSnapshot[]>([])
	const redoStack = ref<TSnapshot[]>([])
	let isApplyingHistory = false
	let lastHistoryKey = ""

	const canUndo = computed(() => undoStack.value.length > 1)
	const canRedo = computed(() => redoStack.value.length > 0)

	function recordHistory(source: TSnapshot) {
		if (isApplyingHistory) return
		const snapshot = clone(source)
		const key = historyKey(snapshot)
		if (key === lastHistoryKey) return
		undoStack.value = [...undoStack.value, snapshot].slice(-limit)
		redoStack.value = []
		lastHistoryKey = key
	}

	function applyHistory(snapshot: TSnapshot) {
		isApplyingHistory = true
		apply(clone(snapshot))
		isApplyingHistory = false
	}

	function undo() {
		if (!canUndo.value) return
		const nextUndo = [...undoStack.value]
		const current = nextUndo.pop()
		const previous = nextUndo[nextUndo.length - 1]
		if (!current || !previous) return
		undoStack.value = nextUndo
		redoStack.value = [clone(current), ...redoStack.value].slice(0, limit)
		lastHistoryKey = historyKey(previous)
		applyHistory(previous)
	}

	function redo() {
		const [next, ...rest] = redoStack.value
		if (!next) return
		redoStack.value = rest
		undoStack.value = [...undoStack.value, clone(next)].slice(-limit)
		lastHistoryKey = historyKey(next)
		applyHistory(next)
	}

	return {
		canUndo,
		canRedo,
		recordHistory,
		undo,
		redo,
	}
}

export function useGraphContextMenuGroups(options: GraphContextMenuGroupsOptions = {}) {
	const defaultOpenGroups = { ...(options.defaultOpenGroups ?? {}) }
	const contextMenuQuery = ref("")
	const contextMenuOpenGroups = ref<Record<string, boolean>>({ ...defaultOpenGroups })
	const contextMenuSearch = computed(() => contextMenuQuery.value.trim().toLowerCase())

	function resetContextMenuGroups() {
		contextMenuQuery.value = ""
		contextMenuOpenGroups.value = { ...defaultOpenGroups }
	}

	function setContextGroupOpen(key: string, open: boolean) {
		contextMenuOpenGroups.value = {
			...contextMenuOpenGroups.value,
			[key]: open,
		}
	}

	function toggleContextGroup(key: string) {
		setContextGroupOpen(key, !isContextGroupOpen(key))
	}

	function isContextGroupOpen(key: string) {
		return contextMenuOpenGroups.value[key] ?? false
	}

	return {
		contextMenuQuery,
		contextMenuSearch,
		contextMenuOpenGroups,
		resetContextMenuGroups,
		setContextGroupOpen,
		toggleContextGroup,
		isContextGroupOpen,
	}
}
