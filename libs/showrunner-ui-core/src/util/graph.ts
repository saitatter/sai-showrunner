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

export interface GraphPortPositionOptions {
	selector: string
	nodeIdDatasetKey: string
	portKeyDatasetKey: string
	kindDatasetKey: string
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
	options: { minControl?: number; controlScale?: number } = {}
): string {
	const dx = Math.abs(x2 - x1)
	const cp = Math.max(options.minControl ?? 60, dx * (options.controlScale ?? 0.4))
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
