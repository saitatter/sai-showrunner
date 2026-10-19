import { OverlayRuntime, WidgetRegistry } from "showrunner-overlay-widget-loader"
import { builtInOverlayPlugins } from "./generated/overlay_plugins.generated"
import { BrowserOverlaySocket } from "./loader/utils/websocket"
import { readFlag } from "./loader/utils/runtime-helpers"
import "../../../plugins/overlays/overlay/src/widgets.css"

const params = new URLSearchParams(window.location.search)
const root = document.getElementById("overlay")
if (!root) throw new Error("Missing overlay root.")

document.body.style.margin = "0"
document.body.style.overflow = "hidden"
root.style.height = "100vh"
root.style.position = "relative"
root.style.width = "100vw"

const registry = new WidgetRegistry()
registry.registerPlugins(builtInOverlayPlugins)

const overlayId = window.location.pathname.split("/").filter(Boolean).pop() || "preview"
const runtime = new OverlayRuntime({
	root,
	registry,
	overlayId,
	isEditor: readFlag(params, "editor"),
	statusVisible: readFlag(params, "statusVisible"),
	transport: new BrowserOverlaySocket(overlayId),
})

if (!readFlag(params, "demo")) void runtime.start().catch((error) => console.error("Overlay runtime failed to start", error))

Object.assign(window, { showRunnerOverlayRuntime: runtime, showRunnerOverlayRegistry: registry })
