import {
	OverlayWidget,
	OverlayWidgetFactory,
	WidgetContext,
	applyStyles,
	clearElement,
	createElement,
} from "showrunner-overlay-core"

type HeartRateState = {
	bpm?: number
	stale?: boolean
}

type HeartRateConfig = {
	showLabel?: boolean
	accentColor?: string
}

type HeartRateZoneState = {
	bpm?: number
	name?: string
	index?: number
	color?: string
}

type HeartRateZoneConfig = {
	showLabel?: boolean
	accentColor?: string
}

type HeartRateGraphConfig = {
	showLabel?: boolean
	accentColor?: string
	maxBpm?: number
}

class HeartRateWidget implements OverlayWidget<HeartRateConfig> {
	private container!: HTMLElement
	private config: HeartRateConfig = {}
	private state: HeartRateState = { stale: true }
	private unsubscribe?: () => void

	mount(container: HTMLElement, config: HeartRateConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		context.bridge.acquireState("heartrate", "heartRate")
		this.unsubscribe = context.bridge.watchState<HeartRateState>("heartrate", "heartRate", (value) => {
			this.state = value ?? { stale: true }
			this.render()
		})
		this.render()
	}

	update(config: HeartRateConfig): void {
		this.config = config ?? {}
		this.render()
	}

	destroy(): void {
		this.unsubscribe?.()
		this.unsubscribe = undefined
		clearElement(this.container)
	}

	private render(): void {
		const root = createElement("div", "showrunner-heart-rate")
		const color = this.config.accentColor || "#f43f5e"
		const stale = this.state.stale !== false || typeof this.state.bpm !== "number"
		const value = createElement("div", "showrunner-heart-rate__value")
		const label = createElement("div", "showrunner-heart-rate__label")
		applyStyles(root, {
			alignItems: "center",
			background: "rgba(13, 17, 23, .82)",
			border: `2px solid ${color}`,
			borderRadius: "8px",
			boxSizing: "border-box",
			color: "#fff",
			display: "flex",
			fontFamily: "Inter, Arial, sans-serif",
			gap: "10px",
			height: "100%",
			justifyContent: "center",
			padding: "12px 18px",
			width: "100%",
		})
		applyStyles(value, {
			color,
			fontSize: "42px",
			fontWeight: "700",
			lineHeight: "1",
		})
		applyStyles(label, {
			fontSize: "16px",
			fontWeight: "600",
			letterSpacing: ".08em",
			textTransform: "uppercase",
		})
		value.textContent = stale ? "--" : String(this.state.bpm)
		label.textContent = this.config.showLabel === false ? "" : "BPM"
		root.append(value, label)
		clearElement(this.container)
		this.container.append(root)
	}
}

export const heartRateWidget: OverlayWidgetFactory<HeartRateConfig> = {
	id: "heartRate",
	create: () => new HeartRateWidget(),
}

class HeartRateZoneWidget implements OverlayWidget<HeartRateZoneConfig> {
	private container!: HTMLElement
	private config: HeartRateZoneConfig = {}
	private state: HeartRateZoneState = {}
	private unsubscribe?: () => void

	mount(container: HTMLElement, config: HeartRateZoneConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		context.bridge.acquireState("heartrate", "zone")
		this.unsubscribe = context.bridge.watchState<HeartRateZoneState>("heartrate", "zone", (value) => {
			this.state = value ?? {}
			this.render()
		})
		this.render()
	}

	update(config: HeartRateZoneConfig): void {
		this.config = config ?? {}
		this.render()
	}

	destroy(): void {
		this.unsubscribe?.()
		this.unsubscribe = undefined
		clearElement(this.container)
	}

	private render(): void {
		const root = createElement("div", "showrunner-heart-rate-zone")
		const accent = this.state.color || this.config.accentColor || "#f43f5e"
		const name = createElement("div", "showrunner-heart-rate-zone__name")
		const value = createElement("div", "showrunner-heart-rate-zone__value")
		applyStyles(root, {
			alignItems: "center",
			background: "rgba(13, 17, 23, .82)",
			border: `2px solid ${accent}`,
			borderRadius: "8px",
			boxSizing: "border-box",
			color: "#fff",
			display: "flex",
			fontFamily: "Inter, Arial, sans-serif",
			gap: "14px",
			height: "100%",
			justifyContent: "center",
			padding: "12px 18px",
			width: "100%",
		})
		applyStyles(name, {
			color: accent,
			fontSize: "24px",
			fontWeight: "700",
		})
		applyStyles(value, {
			fontSize: "18px",
			fontWeight: "600",
		})
		name.textContent = this.state.name || "No zone"
		value.textContent = this.state.bpm == null ? "-- BPM" : `${this.state.bpm} BPM`
		if (this.config.showLabel !== false && this.state.index != null) {
			name.textContent = `Zone ${this.state.index} · ${name.textContent}`
		}
		root.append(name, value)
		clearElement(this.container)
		this.container.append(root)
	}
}

class HeartRateGraphWidget implements OverlayWidget<HeartRateGraphConfig> {
	private container!: HTMLElement
	private config: HeartRateGraphConfig = {}
	private state: HeartRateState = { stale: true }
	private history: number[] = []
	private unsubscribe?: () => void

	mount(container: HTMLElement, config: HeartRateGraphConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		context.bridge.acquireState("heartrate", "heartRate")
		this.unsubscribe = context.bridge.watchState<HeartRateState>("heartrate", "heartRate", (value) => {
			this.state = value ?? { stale: true }
			if (typeof this.state.bpm === "number") {
				this.history = [...this.history, this.state.bpm].slice(-60)
			}
			this.render()
		})
		this.render()
	}

	update(config: HeartRateGraphConfig): void {
		this.config = config ?? {}
		this.render()
	}

	destroy(): void {
		this.unsubscribe?.()
		this.unsubscribe = undefined
		clearElement(this.container)
	}

	private render(): void {
		const root = createElement("div", "showrunner-heart-rate-graph")
		const title = createElement("div", "showrunner-heart-rate-graph__title")
		const chart = createElement("div", "showrunner-heart-rate-graph__chart")
		const accent = this.config.accentColor || "#f43f5e"
		const maxBpm = Math.max(1, this.config.maxBpm || 200)
		applyStyles(root, {
			background: "rgba(13, 17, 23, .82)",
			border: `2px solid ${accent}`,
			borderRadius: "8px",
			boxSizing: "border-box",
			color: "#fff",
			display: "flex",
			flexDirection: "column",
			fontFamily: "Inter, Arial, sans-serif",
			height: "100%",
			padding: "12px 14px",
			width: "100%",
		})
		applyStyles(title, {
			color: accent,
			fontSize: "16px",
			fontWeight: "700",
			marginBottom: "8px",
		})
		applyStyles(chart, {
			alignItems: "end",
			display: "flex",
			flex: "1",
			gap: "2px",
			minHeight: "20px",
		})
		title.textContent = this.config.showLabel === false ? "" : "Heart Rate"
		for (const bpm of this.history) {
			const bar = createElement("div", "showrunner-heart-rate-graph__bar")
			applyStyles(bar, {
				background: accent,
				borderRadius: "2px 2px 0 0",
				flex: "1",
				minHeight: "2px",
				height: `${Math.min(100, Math.max(2, (bpm / maxBpm) * 100))}%`,
				opacity: this.state.stale ? ".35" : "1",
			})
			chart.append(bar)
		}
		if (this.history.length === 0) {
			const empty = createElement("div", "showrunner-heart-rate-graph__empty")
			empty.textContent = "Waiting for heart-rate data…"
			applyStyles(empty, { color: "rgba(255, 255, 255, .65)", fontSize: "14px" })
			chart.append(empty)
		}
		root.append(title, chart)
		clearElement(this.container)
		this.container.append(root)
	}
}

export const heartRateZoneWidget: OverlayWidgetFactory<HeartRateZoneConfig> = {
	id: "heartRateZone",
	create: () => new HeartRateZoneWidget(),
}

export const heartRateGraphWidget: OverlayWidgetFactory<HeartRateGraphConfig> = {
	id: "heartRateGraph",
	create: () => new HeartRateGraphWidget(),
}
