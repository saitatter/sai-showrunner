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
