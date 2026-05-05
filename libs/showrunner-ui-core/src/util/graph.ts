export interface GraphPoint {
	x: number
	y: number
}

export interface GraphPortPositionOptions {
	selector: string
	nodeIdDatasetKey: string
	portKeyDatasetKey: string
	kindDatasetKey: string
}

export function graphPortPositionKey(nodeId: string, portKey: string, kind: "in" | "out") {
	return `${kind}:${nodeId}:${portKey}`
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
