// GENERATED FILE - DO NOT EDIT.

/** Type-level contracts generated from plugin package manifests. */
export interface GeneratedOverlayWidgetConfigMap {
	"heartrate.heartRate": { "showLabel"?: boolean; "accentColor"?: string; "animate"?: boolean; "showBattery"?: boolean; "showConnection"?: boolean }
	"heartrate.heartRateGraph": { "showLabel"?: boolean; "accentColor"?: string; "maxBpm"?: number; "showConnection"?: boolean }
	"heartrate.heartRateZone": { "showLabel"?: boolean; "accentColor"?: string }
	"overlays.alert": { "media"?: readonly unknown[]; "transition"?: Record<string, unknown>; "textBelowMedia"?: boolean; "title"?: Record<string, unknown>; "subtitle"?: Record<string, unknown>; "duration"?: number }
	"overlays.bar": { "value"?: number; "target"?: number; "direction"?: "Right" | "Left" | "Up" | "Down"; "outerRadius"?: { "topLeft"?: number; "topRight"?: number; "bottomLeft"?: number; "bottomRight"?: number }; "backgroundStyle"?: { "color"?: string; "elements"?: readonly { "image"?: string; "gradient"?: { "gradientType"?: "linear" | "radial"; "angle"?: number; "stops"?: readonly { "color"?: string; "position"?: number }[] } }[] }; "outline"?: { "color"?: string; "style"?: "solid" | "dotted" | "dashed"; "width"?: number }; "fillStyle"?: { "color"?: string; "elements"?: readonly { "image"?: string; "gradient"?: { "gradientType"?: "linear" | "radial"; "angle"?: number; "stops"?: readonly { "color"?: string; "position"?: number }[] } }[] }; "fillLine"?: { "color"?: string; "style"?: "solid" | "dotted" | "dashed"; "width"?: number } }
	"overlays.chatFeed": { "fontFamily"?: string; "fontSize"?: number; "backgroundColor"?: string; "backgroundOpacity"?: number; "fadeTime"?: number; "maxMessages"?: number; "orientation"?: "horizontal" | "vertical"; "twitchColor"?: string; "youtubeColor"?: string; "showBadges"?: boolean }
	"overlays.emote-bounce": { "lifeTime"?: { min?: number; max?: number }; "emoteSize"?: { min?: number; max?: number }; "velocityMax"?: number; "shakeTime"?: number; "shakeStrength"?: number; "gravityXScale"?: number; "gravityYScale"?: number; "spamPrevention"?: { "emoteRatio"?: number; "emoteCap"?: number; "emoteCapPerMessage"?: number }; "launchers"?: readonly { "x"?: number; "y"?: number; "angle"?: number; "spread"?: number; "velocity"?: { min?: number; max?: number } }[] }
	"overlays.label": { "message"?: string; "font"?: { "fontFamily"?: string; "fontSize"?: number; "fontColor"?: string; "stroke"?: { "width"?: number; "color"?: string }; "shadow"?: { "blur"?: number; "color"?: string; "offsetX"?: number; "offsetY"?: number } }; "textAlign"?: { "textAlign"?: "left" | "center" | "right" | "justify" }; "block"?: { "margin"?: { "top"?: number; "bottom"?: number; "left"?: number; "right"?: number }; "padding"?: { "top"?: number; "bottom"?: number; "left"?: number; "right"?: number }; "horizontalAlign"?: "left" | "center" | "right"; "verticalAlign"?: "top" | "center" | "bottom" } }
	"overlays.leaderboard": { "sortBy"?: string; "sortOrder"?: number; "count"?: number; "variables"?: readonly { "variable"?: string; "font"?: { "fontFamily"?: string; "fontSize"?: number; "fontColor"?: string; "fontWeight"?: number; "stroke"?: { "width"?: number; "color"?: string }; "shadow"?: { "blur"?: number; "color"?: string; "offsetX"?: number; "offsetY"?: number } }; "textAlign"?: { "textAlign"?: "left" | "center" | "right" | "justify" }; "background"?: { "color"?: string; "elements"?: readonly { "image"?: string }[] }; "block"?: { "padding"?: { "top"?: number; "bottom"?: number; "left"?: number; "right"?: number }; "verticalAlign"?: "top" | "center" | "bottom" } }[]; "nameFont"?: { "fontFamily"?: string; "fontSize"?: number; "fontColor"?: string; "fontWeight"?: number; "stroke"?: { "width"?: number; "color"?: string }; "shadow"?: { "blur"?: number; "color"?: string; "offsetX"?: number; "offsetY"?: number } }; "nameTextAlign"?: { "textAlign"?: "left" | "center" | "right" | "justify" }; "nameBackground"?: { "color"?: string; "elements"?: readonly { "image"?: string }[] }; "nameBlock"?: { "padding"?: { "top"?: number; "bottom"?: number; "left"?: number; "right"?: number }; "verticalAlign"?: "top" | "center" | "bottom" } }
	"overlays.paidAlert": { "fontFamily"?: string; "accentColor"?: string; "backgroundColor"?: string; "backgroundOpacity"?: number; "duration"?: number; "previewTitle"?: string; "previewViewer"?: string; "previewMessage"?: string; "previewAmount"?: string; "previewCurrency"?: string }
	"overlays.sceneBanner": { "fontFamily"?: string; "accentColor"?: string; "backgroundColor"?: string; "backgroundOpacity"?: number; "duration"?: number; "previewTitle"?: string; "previewSubtitle"?: string }
	"overlays.shaderLayer": { "preset"?: "aurora" | "grid" | "plasma" | "nebula" | "scanlines" | "vortex" | "custom"; "customFragmentShader"?: string; "accentColor"?: string; "secondaryColor"?: string; "intensity"?: number; "speed"?: number; "opacity"?: number; "blendMode"?: string; "text"?: string; "shaderGraph"?: Record<string, unknown>; "shaderUniforms"?: Record<string, unknown>; "shaderUniformBindings"?: Record<string, unknown> }
	"random.wheel": { "slices"?: number; "items"?: readonly unknown[]; "style"?: readonly unknown[]; "damping"?: Record<string, unknown>; "clicker"?: Record<string, unknown> }
}

export type GeneratedOverlayWidgetKey = keyof GeneratedOverlayWidgetConfigMap
export type GeneratedOverlayWidgetConfig<K extends GeneratedOverlayWidgetKey> = GeneratedOverlayWidgetConfigMap[K]

export interface GeneratedOverlayEventMap {
	"showrunner_chat_message": { "id"?: string; "platform"?: string; "user"?: string; "username"?: string; "displayName"?: string; "message"?: string; "text"?: string; "badges"?: readonly string[]; "targetOverlayId"?: string; "targetWidgetId"?: string }
	"showrunner_paid_alert": { "displayName"?: string; "title"?: string; "message"?: string; "amount"?: string; "currency"?: string; "targetOverlayId"?: string; "targetWidgetId"?: string }
	"showrunner_scene_event": { "type"?: string; "title"?: string; "subtitle"?: string; "accentColor"?: string; "targetOverlayId"?: string; "targetWidgetId"?: string }
	"twitch_message": unknown
}

export type GeneratedOverlayEventName = keyof GeneratedOverlayEventMap

export interface GeneratedOverlayCommandMap {
	"showAlert": { args: readonly [string, string, string?, number?]; result: number }
	"spawnEmotes": { args: readonly unknown[]; result: unknown }
	"spinWheel": { args: readonly [number?]; result: unknown }
}

export type GeneratedOverlayCommandName = keyof GeneratedOverlayCommandMap

