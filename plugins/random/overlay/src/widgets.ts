import {
	OverlayWidget,
	OverlayWidgetDefinition,
	WidgetContext,
	applyStyles,
	clearElement,
	createElement,
} from "showrunner-overlay-core"
import { OverlayBlockStyle, OverlayTextAlignment, OverlayTextStyle } from "showrunner-plugin-overlays-shared"

type AnyConfig = Record<string, any>

const defaultStyle = [
	{
		color: "#BA7D00",
		font: { fontSize: 45, fontColor: "#FFF1CA", fontFamily: "Arial Rounded MT", fontWeight: 300, stroke: { width: 2, color: "#251600" } },
		textAlign: OverlayTextAlignment.factoryCreate({ textAlign: "center" }),
		block: OverlayBlockStyle.factoryCreate({ verticalAlign: "center" }),
	},
	{
		color: "#A70010",
		font: { fontSize: 45, fontColor: "#FFC5C5", fontFamily: "Arial Rounded MT", fontWeight: 300, stroke: { width: 2, color: "#270000" } },
		textAlign: OverlayTextAlignment.factoryCreate({ textAlign: "center" }),
		block: OverlayBlockStyle.factoryCreate({ verticalAlign: "center" }),
	},
]

function positiveNumber(value: unknown, fallback: number): number {
	const number = Number(value)
	return Number.isFinite(number) && number > 0 ? number : fallback
}

function loopIndex(value: number, length: number): number {
	if (length <= 0) return 0
	const index = Math.ceil(value) % length
	return index < 0 ? length + index : index
}

function wheelItems(config: AnyConfig): AnyConfig[] {
	return Array.isArray(config.items) && config.items.length ? config.items : [{ text: "" }]
}

function wheelStyles(config: AnyConfig): AnyConfig[] {
	return Array.isArray(config.style) && config.style.length ? config.style : defaultStyle
}

class WheelWidget implements OverlayWidget<AnyConfig> {
	private container!: HTMLElement
	private context!: WidgetContext
	private config: AnyConfig = {}
	private angle = 0
	private angularVelocity = 0
	private frame?: number
	private lastTimestamp?: number
	private lastSlot = 0
	private cleanupCommand?: () => void

	mount(container: HTMLElement, config: AnyConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		this.context = context
		this.cleanupCommand = context.bridge.exposeCommand("spinWheel", (args) => {
			this.spin(Number((args as unknown[])[0] ?? 1))
			return undefined
		})
		this.render()
	}

	update(config: AnyConfig): void {
		this.config = config ?? {}
		this.render()
	}

	destroy(): void {
		if (this.frame !== undefined) cancelAnimationFrame(this.frame)
		this.frame = undefined
		this.cleanupCommand?.()
		this.cleanupCommand = undefined
		clearElement(this.container)
	}

	private spin(strength: number): void {
		const amount = Number.isFinite(strength) && strength !== 0 ? strength : 1
		this.angularVelocity += amount * 60
		if (this.frame !== undefined) return
		this.lastTimestamp = undefined
		this.frame = requestAnimationFrame((timestamp) => this.updateWheel(timestamp))
	}

	private updateWheel(timestamp: number): void {
		if (this.lastTimestamp === undefined) {
			this.lastTimestamp = timestamp
			this.frame = requestAnimationFrame((next) => this.updateWheel(next))
			return
		}

		const delta = Math.max(0, Math.min(0.1, (timestamp - this.lastTimestamp) / 1000))
		this.lastTimestamp = timestamp
		this.angle += this.angularVelocity * delta
		const damping = this.config.damping ?? {}
		const base = Number(damping.base ?? 6)
		const coefficient = Number(damping.coefficient ?? 0.1)
		const previous = this.angularVelocity
		this.angularVelocity = Math.max(0, this.angularVelocity - (this.angularVelocity * coefficient + base) * delta)
		const slot = this.selectedSlot()
		if (!this.context.isEditor && slot !== this.lastSlot) {
			this.lastSlot = slot
			this.playClick(slot)
		}
		this.render()

		if (this.angularVelocity > 0) {
			this.frame = requestAnimationFrame((next) => this.updateWheel(next))
			return
		}

		this.frame = undefined
		this.lastTimestamp = undefined
		if (previous > 0 && !this.context.isEditor) {
			const items = wheelItems(this.config)
			void this.context.bridge.callRPC("wheelLanded", items[this.selectedItem()]?.text ?? "")
		}
	}

	private selectedGlobalIndex(): number {
		const slices = positiveNumber(this.config.slices, 12)
		const degrees = 360 / slices
		return Math.ceil((-this.angle - degrees / 2) / degrees)
	}

	private selectedSlot(): number {
		return loopIndex(this.selectedGlobalIndex(), Math.max(1, Math.round(positiveNumber(this.config.slices, 12))))
	}

	private selectedItem(): number {
		return loopIndex(this.selectedGlobalIndex(), wheelItems(this.config).length)
	}

	private playClick(slot: number): void {
		const items = wheelItems(this.config)
		const styles = wheelStyles(this.config)
		const item = items[this.selectedItem()]
		const sound = item?.clickOverride ?? styles[slot % styles.length]?.click
		if (sound) this.context.bridge.playSound(String(sound))
	}

	private render(): void {
		const config = {
			slices: 12,
			items: [],
			style: defaultStyle,
			damping: { base: 6, coefficient: 0.1 },
			clicker: { color: "#A87B0B", width: 80, height: 40, inset: 40 },
			...this.config,
		}
		const slices = Math.max(1, Math.round(positiveNumber(config.slices, 12)))
		const items = wheelItems(config)
		const styles = wheelStyles(config)
		const degrees = 360 / slices
		const root = createElement("div", "wheel-container")
		const wheel = createElement("div", "wheel")
		applyStyles(wheel, { transform: `rotate(${this.angle}deg)` })
		const updateSlot = loopIndex((-this.angle - 180) / degrees, slices)
		const updateItem = loopIndex((-this.angle - 180) / degrees, items.length)

		for (let index = 0; index < slices; index++) {
			const slot = (updateSlot + index) % slices
			const item = items[(updateItem + index) % items.length] ?? {}
			const style = styles[loopIndex(slot, styles.length)] ?? defaultStyle[0]
			const slice = createElement("div", "slice")
			applyStyles(slice, {
				transform: `rotate(${index * degrees}deg)`,
				backgroundColor: item.colorOverride ?? style.color ?? (index % 2 ? "#A70010" : "#BA7D00"),
				clipPath: "polygon(50% 50%, 100% 0, 100% 100%)",
			})
			const label = createElement("div", "label")
			applyStyles(label, { ...OverlayBlockStyle.toCSSProperties(item.blockOverride ?? style.block) })
			const text = createElement("div")
			applyStyles(text, {
				width: "100%",
				whiteSpace: "break-spaces",
				...OverlayTextStyle.toCSSProperties(item.fontOverride ?? style.font),
				...OverlayTextAlignment.toCSSProperties(item.textAlignOverride ?? style.textAlign),
			})
			text.textContent = String(item.text ?? "")
			label.append(text)
			slice.append(label)
			wheel.append(slice)
		}

		const clicker = createElement("div", "clicker")
		const clickerConfig = config.clicker ?? {}
		const width = positiveNumber(clickerConfig.width, 40)
		const height = positiveNumber(clickerConfig.height, 20)
		const inset = Number(clickerConfig.inset ?? 10)
		applyStyles(clicker, {
			backgroundColor: clickerConfig.color ?? "#A87B0B",
			width: `${width}px`,
			height: `${height}px`,
			top: `calc(50% - ${height / 2}px)`,
			right: `${-(width - inset)}px`,
			clipPath: "polygon(0 50%, 100% 0, 100% 100%)",
		})
		root.append(wheel, clicker)
		clearElement(this.container)
		this.container.append(root)
	}
}

export const wheelWidget: OverlayWidgetDefinition = {
	id: "wheel",
	name: "Wheel",
	description: "A wheel for randomly selecting things",
	icon: "mdi mdi-tire",
	defaultSize: { width: 500, height: 500 },
	config: {
		slices: { type: "number", default: 12 },
		items: { type: "array" },
		style: { type: "array" },
		damping: { type: "object" },
		clicker: { type: "object" },
	},
	capabilities: { commands: ["spinWheel"], resizable: true },
	create: () => new WheelWidget(),
}
