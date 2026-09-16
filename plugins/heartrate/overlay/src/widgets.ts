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
	animate?: boolean
	showBattery?: boolean
	showConnection?: boolean
}

type HeartRateConnectionState = {
	status?: string
}

type HeartRateDeviceState = {
	connected?: boolean
	batteryPercent?: number
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
	showConnection?: boolean
}

const heartRatePulseKeyframes = `
@keyframes showrunner-heart-rate-pulse {
	0%, 100% { transform: scale(1); }
	15% { transform: scale(1.18); }
	30% { transform: scale(1); }
}
`

function connectionLabel(connection: HeartRateConnectionState, device: HeartRateDeviceState): string {
	const status = connection.status
	if (status === "reconnecting") return "Reconnecting"
	if (status === "connected" || status === "streaming" || device.connected) return "Connected"
	if (status === "connecting") return "Connecting"
	return "Disconnected"
}

function isConnected(connection: HeartRateConnectionState, device: HeartRateDeviceState): boolean {
	if (connection.status === undefined && device.connected === undefined) return true
	return connection.status === "connected" || connection.status === "streaming" || device.connected === true
}

class HeartRateWidget implements OverlayWidget<HeartRateConfig> {
	private container!: HTMLElement
	private config: HeartRateConfig = {}
	private state: HeartRateState = { stale: true }
	private connection: HeartRateConnectionState = {}
	private device: HeartRateDeviceState = {}
	private unsubscribes: Array<() => void> = []

	mount(container: HTMLElement, config: HeartRateConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		context.bridge.acquireState("heartrate", "heartRate")
		context.bridge.acquireState("heartrate", "connection")
		context.bridge.acquireState("heartrate", "device")
		this.unsubscribes = [
			context.bridge.watchState<HeartRateState>("heartrate", "heartRate", (value) => {
				this.state = value ?? { stale: true }
				this.render()
			}),
			context.bridge.watchState<HeartRateConnectionState>("heartrate", "connection", (value) => {
				this.connection = value ?? {}
				this.render()
			}),
			context.bridge.watchState<HeartRateDeviceState>("heartrate", "device", (value) => {
				this.device = value ?? {}
				this.render()
			}),
		]
		this.render()
	}

	update(config: HeartRateConfig): void {
		this.config = config ?? {}
		this.render()
	}

	destroy(): void {
		for (const unsubscribe of this.unsubscribes) unsubscribe()
		this.unsubscribes = []
		clearElement(this.container)
	}

	private render(): void {
		const root = createElement("div", "showrunner-heart-rate")
		const color = this.config.accentColor || "#f43f5e"
		const connected = isConnected(this.connection, this.device)
		const stale = this.state.stale !== false || typeof this.state.bpm !== "number" || !connected
		const bpm = stale ? undefined : this.state.bpm
		const status = createElement("div", "showrunner-heart-rate__status")
		const icon = createElement("div", "showrunner-heart-rate__icon")
		const value = createElement("div", "showrunner-heart-rate__value")
		const details = createElement("div", "showrunner-heart-rate__details")
		const label = createElement("div", "showrunner-heart-rate__label")
		applyStyles(root, {
			alignItems: "stretch",
			background: "rgba(13, 17, 23, .82)",
			border: `2px solid ${color}`,
			borderRadius: "8px",
			boxSizing: "border-box",
			color: "#fff",
			display: "flex",
			fontFamily: "Inter, Arial, sans-serif",
			gap: "8px",
			height: "100%",
			justifyContent: "center",
			padding: "10px 16px",
			width: "100%",
		})
		applyStyles(status, {
			alignItems: "center",
			display: this.config.showConnection === false ? "none" : "flex",
			fontSize: "12px",
			gap: "6px",
			justifyContent: "flex-end",
			opacity: ".8",
		})
		applyStyles(icon, {
			color,
			fontSize: "28px",
			lineHeight: "1",
			textAlign: "center",
			animation: this.config.animate !== false && bpm != null
				? `showrunner-heart-rate-pulse ${Math.max(0.25, 60 / bpm)}s ease-in-out infinite`
				: "none",
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
		applyStyles(details, {
			alignItems: "center",
			display: "flex",
			gap: "10px",
			justifyContent: "center",
		})
		const statusDot = createElement("span")
		applyStyles(statusDot, {
			background: connected ? "#35d07f" : "#ffb454",
			borderRadius: "50%",
			display: "inline-block",
			height: "8px",
			width: "8px",
		})
		status.textContent = connectionLabel(this.connection, this.device)
		status.prepend(statusDot)
		icon.textContent = "♥"
		value.textContent = bpm == null ? "--" : String(bpm)
		label.textContent = this.config.showLabel === false ? "" : "BPM"
		details.append(value, label)
		if (this.config.showBattery === true && this.device.batteryPercent != null) {
			const battery = createElement("span", "showrunner-heart-rate__battery")
			battery.textContent = `🔋 ${this.device.batteryPercent}%`
			details.append(battery)
		}
		const style = createElement("style")
		style.textContent = heartRatePulseKeyframes
		root.append(style, status, icon, details)
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
	private connection: HeartRateConnectionState = {}
	private unsubscribe?: () => void
	private unsubscribeConnection?: () => void

	mount(container: HTMLElement, config: HeartRateZoneConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		context.bridge.acquireState("heartrate", "zone")
		context.bridge.acquireState("heartrate", "connection")
		this.unsubscribe = context.bridge.watchState<HeartRateZoneState>("heartrate", "zone", (value) => {
			this.state = value ?? {}
			this.render()
		})
		this.unsubscribeConnection = context.bridge.watchState<HeartRateConnectionState>("heartrate", "connection", (value) => {
			this.connection = value ?? {}
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
		this.unsubscribeConnection?.()
		this.unsubscribeConnection = undefined
		clearElement(this.container)
	}

	private render(): void {
		const root = createElement("div", "showrunner-heart-rate-zone")
		const connected = isConnected(this.connection, {})
		const accent = connected && this.state.color ? this.state.color : this.config.accentColor || "#f43f5e"
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
		name.textContent = connected ? this.state.name || "No zone" : "Disconnected"
		value.textContent = connected && this.state.bpm != null ? `${this.state.bpm} BPM` : "-- BPM"
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
	private connection: HeartRateConnectionState = {}
	private history: number[] = []
	private unsubscribe?: () => void
	private unsubscribeConnection?: () => void

	mount(container: HTMLElement, config: HeartRateGraphConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		context.bridge.acquireState("heartrate", "heartRate")
		context.bridge.acquireState("heartrate", "connection")
		this.unsubscribe = context.bridge.watchState<HeartRateState>("heartrate", "heartRate", (value) => {
			this.state = value ?? { stale: true }
			if (typeof this.state.bpm === "number") {
				this.history = [...this.history, this.state.bpm].slice(-60)
			}
			this.render()
		})
		this.unsubscribeConnection = context.bridge.watchState<HeartRateConnectionState>("heartrate", "connection", (value) => {
			this.connection = value ?? {}
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
		this.unsubscribeConnection?.()
		this.unsubscribeConnection = undefined
		clearElement(this.container)
	}

	private render(): void {
		const root = createElement("div", "showrunner-heart-rate-graph")
		const title = createElement("div", "showrunner-heart-rate-graph__title")
		const chart = createElement("div", "showrunner-heart-rate-graph__chart")
		const accent = this.config.accentColor || "#f43f5e"
		const maxBpm = Math.max(1, this.config.maxBpm || 200)
		const connected = isConnected(this.connection, {})
		const stale = this.state.stale !== false || !connected
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
		title.textContent = this.config.showLabel === false
			? ""
			: `Heart Rate${this.config.showConnection === false ? "" : ` · ${connectionLabel(this.connection, {})}`}`
		for (const bpm of this.history) {
			const bar = createElement("div", "showrunner-heart-rate-graph__bar")
			applyStyles(bar, {
				background: accent,
				borderRadius: "2px 2px 0 0",
				flex: "1",
				minHeight: "2px",
				height: `${Math.min(100, Math.max(2, (bpm / maxBpm) * 100))}%`,
				opacity: stale ? ".35" : "1",
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
