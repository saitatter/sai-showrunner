import {
	OverlayWidget,
	OverlayWidgetFactory,
	OverlayCommandMap,
	OverlayEventMap,
	WidgetContext,
	applyStyles,
	clearElement,
	createElement,
	toRgba,
} from "showrunner-overlay-core"
import {
	OverlayBlockStyle,
	OverlayTextAlignment,
	OverlayTextStyle,
	getBackgroundCSS,
	getBorderCSS,
	getBorderRadiusCSS,
	getOutlineCSS,
	resolveShaderUniformBindings,
	type ShaderUniformBindingMap,
} from "showrunner-plugin-overlays-shared"
import { ShaderRenderer } from "./widgets/shader-renderer"

type AnyConfig = Record<string, any>

abstract class DomWidget implements OverlayWidget<AnyConfig> {
	protected container!: HTMLElement
	protected config: AnyConfig = {}
	protected context!: WidgetContext

	mount(container: HTMLElement, config: AnyConfig, context: WidgetContext): void {
		this.container = container
		this.config = config ?? {}
		this.context = context
		this.container.classList.add("showrunner-widget-root")
		this.onMount()
		this.render()
	}

	update(config: AnyConfig): void {
		this.config = config ?? {}
		this.render()
	}

	destroy(): void {
		this.onDestroy()
		clearElement(this.container)
	}

	protected onMount(): void {}
	protected onDestroy(): void {}
	protected abstract render(): void

	protected listen<K extends keyof HTMLElementEventMap>(element: HTMLElement, type: K, handler: (event: HTMLElementEventMap[K]) => void): void {
		element.addEventListener(type, handler as EventListener)
		this.context.scope.add(() => element.removeEventListener(type, handler as EventListener))
	}

	protected onMessage<K extends keyof OverlayEventMap>(id: K, handler: (payload: OverlayEventMap[K]) => void): void {
		this.context.bridge.onEvent(id, handler)
	}

	protected onCommand<K extends keyof OverlayCommandMap>(id: K, handler: (args: OverlayCommandMap[K]["args"]) => OverlayCommandMap[K]["result"] | Promise<OverlayCommandMap[K]["result"]>): void {
		this.context.bridge.exposeCommand(id, handler)
	}
}

function configWithDefaults(config: AnyConfig, defaults: AnyConfig): AnyConfig {
	return { ...defaults, ...(config ?? {}) }
}

function positiveNumber(value: unknown, fallback: number): number {
	const number = Number(value)
	return Number.isFinite(number) && number > 0 ? number : fallback
}

function widgetFactory(id: string, create: OverlayWidgetFactory["create"]): OverlayWidgetFactory {
	return { id, create }
}

class LabelWidget extends DomWidget {
	protected render(): void {
		clearElement(this.container)
		const config = configWithDefaults(this.config, {
			message: "Label",
			font: OverlayTextStyle.factoryCreate(),
			textAlign: OverlayTextAlignment.factoryCreate(),
			block: OverlayBlockStyle.factoryCreate(),
		})
		const outer = createElement("div", "overlay-label")
		applyStyles(outer, { ...OverlayTextStyle.toCSSProperties(config.font), ...OverlayBlockStyle.toCSSProperties(config.block) })
		const text = createElement("div")
		text.textContent = String(config.message ?? "")
		applyStyles(text, { width: "100%", whiteSpace: "break-spaces", ...OverlayTextAlignment.toCSSProperties(config.textAlign) })
		outer.append(text)
		this.container.append(outer)
	}
}

export const labelWidget = widgetFactory("label", () => new LabelWidget())

class BarWidget extends DomWidget {
	protected render(): void {
		clearElement(this.container)
		const config = configWithDefaults(this.config, {
			value: 25,
			target: 100,
			direction: "Right",
			outerRadius: {},
			backgroundStyle: { color: "#222", elements: [] },
			fillStyle: { color: "#42d392", elements: [] },
		})
		const outer = createElement("div", "outer-bar")
		const inner = createElement("div", "inner-bar")
		const vertical = config.direction === "Up" || config.direction === "Down"
		const reverse = config.direction === "Left" || config.direction === "Up"
		const ratio = Math.max(0, Math.min(1, Number(config.value) / (Number(config.target) || 1))) * 100
		applyStyles(outer, {
			flexDirection: vertical ? (reverse ? "column-reverse" : "column") : reverse ? "row-reverse" : "row",
			...getBorderRadiusCSS(config.outerRadius),
			...getBackgroundCSS(config.backgroundStyle, (file) => this.context.mediaUrl(file)),
			...getOutlineCSS(config.outline),
		})
		applyStyles(inner, {
			...(vertical ? { height: `${ratio}%`, width: "100%" } : { width: `${ratio}%`, height: "100%" }),
			...getBackgroundCSS(config.fillStyle, (file) => this.context.mediaUrl(file)),
		})
		const border: AnyConfig = {}
		if (vertical) border[reverse ? "top" : "bottom"] = config.fillLine
		else border[reverse ? "left" : "right"] = config.fillLine
		applyStyles(inner, getBorderCSS(border))
		outer.append(inner)
		this.container.append(outer)
	}
}

export const barWidget = widgetFactory("bar", () => new BarWidget())

type ChatMessage = OverlayEventMap["showrunner_chat_message"]

class ChatFeedWidget extends DomWidget {
	private messages: Required<ChatMessage>[] = []
	private readonly timers = new Set<number>()

	protected onMount(): void {
		this.onMessage("showrunner_chat_message", (message) => this.addMessage(message))
		if (this.context.isEditor) {
			this.addMessage({ id: "sample-twitch", platform: "twitch", displayName: "ViewerName", message: "Approved Twitch message preview.", badges: ["sub"] })
			this.addMessage({ id: "sample-youtube", platform: "youtube", displayName: "Channel Member", message: "Approved YouTube message preview.", badges: ["member"] })
		}
	}

	protected onDestroy(): void {
		for (const timer of this.timers) window.clearTimeout(timer)
		this.timers.clear()
	}

	private addMessage(message: ChatMessage): void {
		const current = this.context.bridge.getConfig()
		if (!this.context.isEditor && message.targetOverlayId && message.targetOverlayId !== this.context.overlayId) return
		if (!this.context.isEditor && message.targetWidgetId && message.targetWidgetId !== current.id) return
		const entry = {
			id: String(message.id || `${Date.now()}-${Math.random()}`),
			platform: String(message.platform || "unknown").toLowerCase(),
			user: String(message.user || message.username || message.displayName || "unknown"),
			username: String(message.username || message.user || message.displayName || "unknown"),
			displayName: String(message.displayName || message.username || message.user || "unknown"),
			message: String(message.message || message.text || ""),
			text: String(message.text || message.message || ""),
			badges: Array.isArray(message.badges) ? message.badges : String(message.badges || "").split(",").map((badge) => badge.trim()).filter(Boolean),
			targetOverlayId: String(message.targetOverlayId || ""),
			targetWidgetId: String(message.targetWidgetId || ""),
		} satisfies Required<ChatMessage>
		const max = Math.max(1, Number(this.config.maxMessages) || 8)
		this.messages.unshift(entry)
		this.messages = this.messages.slice(0, max)
		const fadeMs = Math.max(0, Number(this.config.fadeTime) || 0) * 1000
		if (fadeMs && !this.context.isEditor) {
			const timer = window.setTimeout(() => {
			this.messages = this.messages.filter((item) => item.id !== entry.id)
			this.timers.delete(timer)
			this.render()
		}, fadeMs)
			this.timers.add(timer)
		}
		this.render()
	}

	protected render(): void {
		const config = configWithDefaults(this.config, {
			fontFamily: "Inter, Arial, sans-serif", fontSize: 24, backgroundColor: "#0d1117", backgroundOpacity: 0.72,
			maxMessages: 8, orientation: "horizontal", twitchColor: "#9146ff", youtubeColor: "#ff0033", showBadges: true,
		})
		const root = createElement("div", `chat-feed chat-feed--${config.orientation}`)
		applyStyles(root, { fontFamily: config.fontFamily, fontSize: `${config.fontSize}px` })
		for (const entry of this.messages.slice(0, Math.max(1, Number(config.maxMessages) || 8))) {
			const article = createElement("article", "chat-feed__message")
			article.dataset.platform = entry.platform
			applyStyles(article, { background: toRgba(config.backgroundColor, config.backgroundOpacity), borderLeftColor: entry.platform === "youtube" ? config.youtubeColor : config.twitchColor })
			const meta = createElement("div", "chat-feed__meta")
			const marker = createElement("span", "chat-feed__platform")
			applyStyles(marker, { backgroundColor: entry.platform === "youtube" ? config.youtubeColor : config.twitchColor })
			meta.append(marker)
			if (config.showBadges) {
				const badges = createElement("span", "chat-feed__badges")
				for (const badge of entry.badges) {
					const badgeElement = createElement("span", "chat-feed__badge")
					badgeElement.textContent = badge
					badges.append(badgeElement)
				}
				meta.append(badges)
			}
			const name = createElement("strong")
			name.textContent = entry.displayName
			meta.append(name)
			const body = createElement("p")
			body.textContent = entry.message
			article.append(meta, body)
			root.append(article)
		}
		clearElement(this.container)
		this.container.append(root)
	}
}

export const chatFeedWidget = widgetFactory("chatFeed", () => new ChatFeedWidget())

type PaidAlertEvent = OverlayEventMap["showrunner_paid_alert"]
type SceneEvent = OverlayEventMap["showrunner_scene_event"]

class PaidAlertWidget extends DomWidget {
	private active?: PaidAlertEvent
	private timer?: number

	protected onMount(): void {
		this.onMessage("showrunner_paid_alert", (message) => this.show(message))
		if (this.context.isEditor) this.show({ displayName: this.config.previewViewer, title: this.config.previewTitle, message: this.config.previewMessage, amount: this.config.previewAmount, currency: this.config.previewCurrency })
	}

	private show(message: PaidAlertEvent): void {
		if (!this.context.isEditor && message.targetOverlayId && message.targetOverlayId !== this.context.overlayId) return
		if (!this.context.isEditor && message.targetWidgetId && message.targetWidgetId !== this.context.bridge.getConfig().id) return
		this.active = message
		if (this.timer) window.clearTimeout(this.timer)
		if (!this.context.isEditor) this.timer = window.setTimeout(() => { this.active = undefined; this.render() }, Math.max(1, Number(this.config.duration) || 7) * 1000)
		this.render()
	}

	protected onDestroy(): void { if (this.timer) window.clearTimeout(this.timer) }

	protected render(): void {
		const config = configWithDefaults(this.config, { fontFamily: "Inter, Arial, sans-serif", accentColor: "#ffd166", backgroundColor: "#131313", backgroundOpacity: 0.86, previewTitle: "Super Chat", previewViewer: "Supporter", previewMessage: "Thanks for the stream!", previewAmount: "10.00", previewCurrency: "USD" })
		const root = createElement("div", `paid-alert${this.active ? " active" : ""}`)
		applyStyles(root, { fontFamily: config.fontFamily, background: toRgba(config.backgroundColor, config.backgroundOpacity), borderColor: config.accentColor })
		const icon = createElement("div", "paid-alert__icon"); icon.textContent = "★"
		const body = createElement("div", "paid-alert__body")
		const title = createElement("strong"); title.textContent = this.active?.title || config.previewTitle
		const viewer = createElement("span"); viewer.textContent = this.active?.displayName || config.previewViewer
		const message = createElement("p"); message.textContent = this.active?.message || config.previewMessage
		body.append(title, viewer, message)
		const amount = createElement("div", "paid-alert__amount"); amount.textContent = `${this.active?.amount || config.previewAmount} ${this.active?.currency || config.previewCurrency}`
		root.append(createElement("div", "paid-alert__shine"), icon, body, amount)
		clearElement(this.container); this.container.append(root)
	}
}

export const paidAlertWidget = widgetFactory("paidAlert", () => new PaidAlertWidget())

class SceneBannerWidget extends DomWidget {
	private active?: SceneEvent
	private timer?: number

	protected onMount(): void {
		this.onMessage("showrunner_scene_event", (event) => {
			if (event?.type === "scene.end") { this.active = undefined; this.render(); return }
			if (!this.context.isEditor && event?.targetOverlayId && event.targetOverlayId !== this.context.overlayId) return
			if (!this.context.isEditor && event?.targetWidgetId && event.targetWidgetId !== this.context.bridge.getConfig().id) return
			this.active = event
			if (this.timer) window.clearTimeout(this.timer)
			if (!this.context.isEditor) this.timer = window.setTimeout(() => { this.active = undefined; this.render() }, Math.max(1, Number(this.config.duration) || 6) * 1000)
			this.render()
		})
		if (this.context.isEditor) this.active = { title: this.config.previewTitle, subtitle: this.config.previewSubtitle, accentColor: this.config.accentColor }
	}

	protected onDestroy(): void { if (this.timer) window.clearTimeout(this.timer) }

	protected render(): void {
		const config = configWithDefaults(this.config, { fontFamily: "Inter, Arial, sans-serif", accentColor: "#9146ff", backgroundColor: "#101010", backgroundOpacity: 0.82, previewTitle: "Starting Soon", previewSubtitle: "Scene automation preview" })
		const root = createElement("div", `scene-banner${this.active ? " active" : ""}`)
		const accent = this.active?.accentColor || config.accentColor
		applyStyles(root, { fontFamily: config.fontFamily, background: toRgba(config.backgroundColor, config.backgroundOpacity), borderColor: accent })
		const rule = createElement("div", "scene-banner__rule"); applyStyles(rule, { backgroundColor: accent })
		const content = createElement("div")
		const title = createElement("strong"); title.textContent = this.active?.title || config.previewTitle
		const subtitle = createElement("span"); subtitle.textContent = this.active?.subtitle || config.previewSubtitle
		content.append(title, subtitle); root.append(rule, content)
		clearElement(this.container); this.container.append(root)
	}
}

export const sceneBannerWidget = widgetFactory("sceneBanner", () => new SceneBannerWidget())

const shaderPresets: Record<string, string> = {
	aurora: `precision mediump float;
uniform vec2 u_resolution; uniform float u_time; uniform vec3 u_accent; uniform vec3 u_secondary; uniform float u_intensity; uniform float u_speed;
void main() { vec2 uv = gl_FragCoord.xy / u_resolution.xy; float wave = sin((uv.x * 7.0 + u_time * u_speed) + sin(uv.y * 5.0 + u_time * 0.35)); float glow = smoothstep(0.15, 1.0, wave * 0.5 + 0.5) * u_intensity; vec3 color = mix(u_secondary, u_accent, uv.y + wave * 0.18); gl_FragColor = vec4(color, glow * 0.85); }`,
	grid: `precision mediump float;
uniform vec2 u_resolution; uniform float u_time; uniform vec3 u_accent; uniform vec3 u_secondary; uniform float u_intensity; uniform float u_speed;
void main() { vec2 uv = gl_FragCoord.xy / u_resolution.xy; vec2 grid = abs(fract((uv + vec2(u_time * 0.03 * u_speed, 0.0)) * 18.0) - 0.5); float lines = 1.0 - smoothstep(0.0, 0.035, min(grid.x, grid.y)); float pulse = 0.55 + 0.45 * sin(u_time * u_speed + uv.x * 4.0); vec3 color = mix(u_secondary, u_accent, pulse); gl_FragColor = vec4(color, lines * u_intensity); }`,
	plasma: `precision mediump float;
uniform vec2 u_resolution; uniform float u_time; uniform vec3 u_accent; uniform vec3 u_secondary; uniform float u_intensity; uniform float u_speed;
void main() { vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y); float value = sin(uv.x * 6.0 + u_time * u_speed) + sin(uv.y * 5.0 - u_time * 0.7 * u_speed) + sin((uv.x + uv.y) * 4.0 + u_time * 0.5 * u_speed); value = value / 3.0 * 0.5 + 0.5; vec3 color = mix(u_secondary, u_accent, value); gl_FragColor = vec4(color, value * u_intensity); }`,
	nebula: `precision mediump float;
uniform vec2 u_resolution; uniform float u_time; uniform vec3 u_accent; uniform vec3 u_secondary; uniform float u_intensity; uniform float u_speed;
float field(vec2 p) { float value = 0.0; float scale = 1.0; for (int i = 0; i < 4; i++) { value += abs(sin(p.x * scale + u_time * 0.15 * u_speed) + cos(p.y * scale - u_time * 0.2 * u_speed)) / scale; p = mat2(0.8, -0.6, 0.6, 0.8) * p * 1.35; scale *= 1.7; } return value; }
void main() { vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y); float cloud = smoothstep(0.9, 2.4, field(uv * 1.4)); vec3 color = mix(u_secondary * 0.35, u_accent, cloud); gl_FragColor = vec4(color, cloud * u_intensity * 0.78); }`,
	scanlines: `precision mediump float;
uniform vec2 u_resolution; uniform float u_time; uniform vec3 u_accent; uniform vec3 u_secondary; uniform float u_intensity; uniform float u_speed;
void main() { vec2 uv = gl_FragCoord.xy / u_resolution.xy; float line = smoothstep(0.48, 0.5, sin((uv.y + u_time * 0.04 * u_speed) * 220.0) * 0.5 + 0.5); float sweep = smoothstep(0.02, 0.0, abs(fract(uv.y + u_time * 0.08 * u_speed) - 0.5)); float edge = smoothstep(0.0, 0.35, uv.x) * smoothstep(1.0, 0.65, uv.x); vec3 color = mix(u_secondary, u_accent, uv.x + sweep * 0.4); gl_FragColor = vec4(color, (line * 0.2 + sweep * 0.8) * edge * u_intensity); }`,
	vortex: `precision mediump float;
uniform vec2 u_resolution; uniform float u_time; uniform vec3 u_accent; uniform vec3 u_secondary; uniform float u_intensity; uniform float u_speed;
void main() { vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / min(u_resolution.x, u_resolution.y); float radius = length(uv); float angle = atan(uv.y, uv.x); float swirl = sin(angle * 5.0 + radius * 11.0 - u_time * u_speed * 1.4); float ring = smoothstep(0.45, 0.02, abs(swirl * 0.08 + radius - 0.52)); vec3 color = mix(u_secondary, u_accent, swirl * 0.5 + 0.5); gl_FragColor = vec4(color, ring * (1.0 - smoothstep(0.2, 1.05, radius)) * u_intensity); }`,
}

class ShaderLayerWidget extends DomWidget {
	private canvas?: HTMLCanvasElement
	private renderer?: ShaderRenderer
	private error = ""
	private acquiredBindingStates = new Set<string>()

	protected onMount(): void {
		this.render()
	}

	protected onDestroy(): void {
		this.renderer?.dispose()
		this.renderer = undefined
		for (const key of this.acquiredBindingStates) {
			const [plugin, state] = key.split(":")
			if (plugin && state) this.context.bridge.releaseState(plugin, state)
		}
		this.acquiredBindingStates.clear()
	}

	protected render(): void {
		this.renderer?.dispose(); this.renderer = undefined
		const config = configWithDefaults(this.config, { preset: "aurora", customFragmentShader: "", accentColor: "#9146ff", secondaryColor: "#00d1ff", intensity: 0.8, speed: 1, opacity: 1, blendMode: "normal", text: "" })
		this.syncBindingStates(config.shaderUniformBindings ?? {})
		const root = createElement("div", "shader-layer"); applyStyles(root, { opacity: config.opacity, mixBlendMode: config.blendMode })
		this.canvas = createElement("canvas", "shader-layer__canvas")
		root.append(this.canvas)
		if (config.text) { const text = createElement("div", "shader-layer__text"); text.textContent = config.text; root.append(text) }
		clearElement(this.container); this.container.append(root)
		try {
			this.error = ""
			this.renderer = new ShaderRenderer({ canvas: this.canvas, fragmentSource: this.shaderSource(config), getAccentColor: () => hexToVec3(config.accentColor, [0.57, 0.27, 1]), getSecondaryColor: () => hexToVec3(config.secondaryColor, [0, 0.82, 1]), getIntensity: () => Number(config.intensity ?? 0.8), getSpeed: () => Number(config.speed ?? 1), getCustomUniforms: () => resolveShaderUniformBindings(config.shaderUniforms ?? {}, config.shaderUniformBindings ?? {}, { config, states: this.stateSnapshot(config.shaderUniformBindings ?? {}) }) })
		} catch (error) { this.error = error instanceof Error ? error.message : String(error); const fallback = createElement("div", "shader-layer__fallback"); fallback.textContent = `Shader unavailable: ${this.error}`; root.append(fallback) }
	}

	private shaderSource(config: AnyConfig): string {
		if (config.preset === "custom" && String(config.customFragmentShader || "").trim()) return config.customFragmentShader
		return shaderPresets[config.preset] ?? shaderPresets.aurora
	}

	private syncBindingStates(bindings: ShaderUniformBindingMap): void {
		const next = new Set(Object.values(bindings).filter((binding) => binding.source === "state").map((binding) => `${binding.plugin}:${binding.state}`))
		for (const key of this.acquiredBindingStates) {
			if (next.has(key)) continue
			const [plugin, state] = key.split(":")
			if (plugin && state) this.context.bridge.releaseState(plugin, state)
		}
		for (const key of next) {
			if (this.acquiredBindingStates.has(key)) continue
			const [plugin, state] = key.split(":")
			if (plugin && state) this.context.bridge.acquireState(plugin, state)
		}
		this.acquiredBindingStates = next
	}

	private stateSnapshot(bindings: ShaderUniformBindingMap): Record<string, Record<string, unknown>> {
		const states: Record<string, Record<string, unknown>> = {}
		for (const binding of Object.values(bindings)) {
			if (binding.source !== "state") continue
			states[binding.plugin] ??= {}
			states[binding.plugin][binding.state] = this.context.state.get(binding.plugin, binding.state)
		}
		return states
	}
}

function hexToVec3(hex: string, fallback: [number, number, number]): [number, number, number] {
	const match = String(hex || "").match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i)
	if (!match) return fallback
	let value = match[1]; if (value.length === 3) value = value.split("").map((part) => part + part).join("")
	const parsed = Number.parseInt(value, 16)
	return [((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255]
}

export const shaderLayerWidget = widgetFactory("shaderLayer", () => new ShaderLayerWidget())

class AlertWidget extends DomWidget {
	private title = "Title"; private message = "Message"; private media?: string; private timer?: number

	protected onMount(): void {
		this.onCommand("showAlert", (args) => { const [title, message, _color, index] = args; return this.show(String(title), String(message), Number(index) || 0) })
		if (this.context.isEditor) this.show("Title", "Message", 0)
	}

	private show(title: string, message: string, mediaIndex: number): number {
		this.title = title; this.message = message
		const option = this.config.media?.[mediaIndex]
		this.media = option?.media
		if (this.timer) window.clearTimeout(this.timer)
		const duration = Number(option?.duration ?? this.config.duration ?? 4)
		if (!this.context.isEditor) this.timer = window.setTimeout(() => { this.media = undefined; this.render() }, duration * 1000)
		this.render(); return duration
	}

	protected onDestroy(): void { if (this.timer) window.clearTimeout(this.timer) }

	protected render(): void {
		const root = createElement("div", "alert-widget")
		if (this.media) {
			const media = /\.(webm|mp4|ogg)$/i.test(this.media) ? createElement("video") : createElement("img")
			media.className = "alert-widget__media"; media.src = this.context.mediaUrl(this.media); if (media instanceof HTMLVideoElement) { media.autoplay = true; media.muted = this.context.isEditor; media.loop = true }
			root.append(media)
		}
		const title = createElement("strong"); title.textContent = this.title
		const message = createElement("span"); message.textContent = this.message
		root.append(title, message)
		clearElement(this.container); this.container.append(root)
	}
}

export const alertWidget = widgetFactory("alert", () => new AlertWidget())

interface BouncingEmote {
	id: string
	image: HTMLImageElement
	x: number
	y: number
	vx: number
	vy: number
	angle: number
	angularVelocity: number
	width: number
	height: number
	expiresAt: number
}

class EmoteBouncerWidget extends DomWidget {
	private root?: HTMLElement
	private readonly emotes = new Map<string, BouncingEmote>()
	private counter = 0
	private frame?: number
	private lastTimestamp?: number
	private nextShakeAt = 0

	protected onMount(): void {
		this.onMessage("twitch_message", (message) => this.spawnFromMessage(message))
		this.onCommand("spawnEmotes", (args) => {
			const values = args as unknown[]
			this.spawnFromMessage(values.length === 1 ? values[0] : values)
			return undefined
		})
		this.root = createElement("div", "bounce-house")
		this.container.append(this.root)
		this.renderLaunchers()
		if (!this.context.isEditor) this.frame = requestAnimationFrame((timestamp) => this.tick(timestamp))
	}

	protected onDestroy(): void {
		if (this.frame !== undefined) cancelAnimationFrame(this.frame)
		this.frame = undefined
		this.emotes.clear()
	}

	protected render(): void {
		if (!this.root) return
		this.renderLaunchers()
		for (const emote of this.emotes.values()) this.updateImage(emote)
	}

	private renderLaunchers(): void {
		if (!this.root) return
		for (const marker of [...this.root.querySelectorAll(".launch-indicator")]) marker.remove()
		if (!this.context.isEditor) return
		for (const launcher of this.config.launchers ?? []) {
			const marker = createElement("span", "launch-indicator")
			applyStyles(marker, { left: `${Number(launcher.x) || 0}px`, top: `${Number(launcher.y) || 0}px` })
			const cone = createElement("span", "launch-cone")
			const width = positiveRange(launcher.velocity, 1) * 400
			const height = width * Math.sin((Number(launcher.spread ?? 20) * Math.PI) / 360) * 2
			applyStyles(cone, {
				width: `${width}px`,
				height: `${height}px`,
				left: "50%",
				top: `calc(50% - ${height / 2}px)`,
				transform: `rotate(${Number(launcher.angle) || 0}deg)`,
			})
			marker.append(cone)
			this.root.append(marker)
		}
	}

	private spawnFromMessage(message: any): void {
		const chunks = Array.isArray(message) ? message : message?.emotes ?? []
		const emotes = chunks
			.map((chunk: any) => chunk?.type === "emote" ? chunk.emote : chunk)
			.filter((emote: any) => emote?.urls || emote?.url)
		const ratio = Math.max(0, Math.ceil(Number(this.config.spamPrevention?.emoteRatio ?? 1)))
		const capPerMessage = Number(this.config.spamPrevention?.emoteCapPerMessage)
		let spawned = 0
		for (let repeat = 0; repeat < ratio; repeat++) {
			for (const emote of emotes) {
				if (Number.isFinite(capPerMessage) && capPerMessage > 0 && spawned >= capPerMessage) return
				if (this.spawnEmote(emote)) spawned++
			}
		}
	}

	private spawnEmote(emote: any): boolean {
		const imageUrl = emote?.urls?.url4x ?? emote?.urls?.url3x ?? emote?.urls?.url2x ?? emote?.urls?.url1x ?? emote?.url
		if (!imageUrl) return false
		const size = randomRange(this.config.emoteSize, 80)
		const aspectRatio = positiveNumber(emote?.aspectRatio, 1)
		const width = size / aspectRatio
		const launcher = Array.isArray(this.config.launchers) && this.config.launchers.length
			? this.config.launchers[Math.floor(Math.random() * this.config.launchers.length)]
			: undefined
		const angle = launcher ? Number(launcher.angle) + (Math.random() - 0.5) * Number(launcher.spread ?? 20) : 0
		const velocity = launcher ? randomRange(launcher.velocity, 0.4) : (Math.random() - 0.5) * Number(this.config.velocityMax ?? 0.4)
		const radians = (angle * Math.PI) / 180
		const body: BouncingEmote = {
			id: `emote-${this.counter++}`,
			image: createElement("img", "bouncey-body"),
			x: launcher ? Number(launcher.x) || 0 : Math.random() * this.container.clientWidth,
			y: launcher ? Number(launcher.y) || 0 : Math.random() * this.container.clientHeight,
			vx: launcher ? Math.cos(radians) * velocity * 0.5 : velocity,
			vy: launcher ? Math.sin(radians) * velocity * 0.5 : (Math.random() - 0.5) * Number(this.config.velocityMax ?? 0.4),
			angle: 0,
			angularVelocity: 0,
			width,
			height: size,
			expiresAt: performance.now() + randomRange(this.config.lifeTime, 7) * 1000,
		}
		body.image.src = imageUrl
		body.image.draggable = false
		body.image.width = width
		body.image.height = size
		this.enforceCap()
		this.emotes.set(body.id, body)
		this.root?.append(body.image)
		this.updateImage(body)
		return true
	}

	private enforceCap(): void {
		const cap = Number(this.config.spamPrevention?.emoteCap)
		if (!Number.isFinite(cap) || cap < 1) return
		while (this.emotes.size >= cap) {
			const first = this.emotes.keys().next().value as string | undefined
			if (!first) break
			this.removeEmote(first)
		}
	}

	private removeEmote(id: string): void {
		const emote = this.emotes.get(id)
		if (!emote) return
		emote.image.remove()
		this.emotes.delete(id)
	}

	private tick(timestamp: number): void {
		const delta = this.lastTimestamp === undefined ? 0 : Math.min(0.05, Math.max(0, timestamp - this.lastTimestamp) / 1000)
		this.lastTimestamp = timestamp
		const width = Math.max(1, this.container.clientWidth)
		const height = Math.max(1, this.container.clientHeight)
		const gravityX = Number(this.config.gravityXScale ?? 0) * 35
		const gravityY = Number(this.config.gravityYScale ?? 1) * 35
		for (const [id, emote] of this.emotes) {
			if (timestamp >= emote.expiresAt) { this.removeEmote(id); continue }
			emote.vx += gravityX * delta
			emote.vy += gravityY * delta
			emote.x += emote.vx * 60 * delta
			emote.y += emote.vy * 60 * delta
			emote.angle += emote.angularVelocity * delta
			const radiusX = emote.width / 2
			const radiusY = emote.height / 2
			if (emote.x < radiusX || emote.x > width - radiusX) { emote.x = Math.max(radiusX, Math.min(width - radiusX, emote.x)); emote.vx *= -0.8 }
			if (emote.y < radiusY || emote.y > height - radiusY) { emote.y = Math.max(radiusY, Math.min(height - radiusY, emote.y)); emote.vy *= -0.8 }
			this.updateImage(emote)
		}
		const shakeTime = Number(this.config.shakeTime ?? 5)
		if (shakeTime > 0 && timestamp >= this.nextShakeAt) {
			this.nextShakeAt = timestamp + shakeTime * 1000
			const strength = Number(this.config.shakeStrength ?? 1) * 0.08
			for (const emote of this.emotes.values()) { emote.vx += (Math.random() - 0.5) * strength; emote.vy -= Math.random() * strength }
		}
		this.frame = requestAnimationFrame((next) => this.tick(next))
	}

	private updateImage(emote: BouncingEmote): void {
		applyStyles(emote.image, { left: `${emote.x}px`, top: `${emote.y}px`, transform: `translate(-50%, -50%) rotate(${emote.angle}rad)` })
	}
}

function randomRange(value: any, fallback: number): number {
	if (typeof value === "number" && Number.isFinite(value)) return value
	const min = Number(value?.min)
	const max = Number(value?.max ?? min)
	if (!Number.isFinite(min)) return fallback
	return min + Math.random() * Math.max(0, (Number.isFinite(max) ? max : min) - min)
}

function positiveRange(value: any, fallback: number): number {
	return Math.max(0, randomRange(value, fallback))
}


export const emoteBouncerWidget = widgetFactory("emote-bounce", () => new EmoteBouncerWidget())

class LeaderboardWidget extends DomWidget {
	private rows: any[] = []
	protected onMount(): void {
		const reload = async () => { this.rows = await this.context.viewerData.query(0, Number(this.config.count) || 10, this.config.sortBy, Number(this.config.sortOrder) || -1); this.render() }
		void reload()
		this.context.viewerData.observe({ onNewViewerData: () => void reload(), onViewerDataChanged: () => void reload(), onViewerDataRemoved: () => void reload() })
	}

	protected render(): void {
		const config = configWithDefaults(this.config, { variables: [], sortBy: "", sortOrder: -1, count: 10, nameFont: OverlayTextStyle.factoryCreate(), nameTextAlign: OverlayTextAlignment.factoryCreate(), nameBackground: { elements: [] }, nameBlock: OverlayBlockStyle.factoryCreate() })
		const table = createElement("table", "leaderboard")
		for (const row of this.rows.slice(0, Math.max(1, Number(config.count) || 10))) {
			const tr = createElement("tr"); const name = createElement("td"); name.textContent = row["twitch_name"] ?? row.name ?? row.twitch ?? ""; applyStyles(name, { ...OverlayTextStyle.toCSSProperties(config.nameFont), ...OverlayBlockStyle.toCSSPadding(config.nameBlock), ...OverlayTextAlignment.toCSSProperties(config.nameTextAlign), ...getBackgroundCSS(config.nameBackground, (file) => this.context.mediaUrl(file)) }); tr.append(name)
			for (const variable of config.variables ?? []) { const td = createElement("td"); td.textContent = String(row[variable.variable] ?? ""); applyStyles(td, { ...OverlayTextStyle.toCSSProperties(variable.font), ...OverlayBlockStyle.toCSSPadding(variable.block), ...OverlayTextAlignment.toCSSProperties(variable.textAlign), ...getBackgroundCSS(variable.background, (file) => this.context.mediaUrl(file)) }); tr.append(td) }
			table.append(tr)
		}
		const root = createElement("div", "table-container"); root.append(table); clearElement(this.container); this.container.append(root)
	}
}

export const leaderboardWidget = widgetFactory("leaderboard", () => new LeaderboardWidget())

export const overlayWidgetFactories: readonly OverlayWidgetFactory[] = [alertWidget, barWidget, chatFeedWidget, emoteBouncerWidget, labelWidget, leaderboardWidget, paidAlertWidget, sceneBannerWidget, shaderLayerWidget]
