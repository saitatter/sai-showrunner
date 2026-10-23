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

if (!readFlag(params, "demo")) void (async () => {
  const token = window.location.hash.slice(1)
  const response = await fetch(`/overlays/${encodeURIComponent(overlayId)}/session`, {
    method:"POST", headers:{"x-showrunner-overlay":token}, credentials:"same-origin",
  })
  if (!response.ok) throw new Error("Copy the current Browser Source URL from ShowRunner")
  await runtime.start()
})().catch(() => {
  root.setAttribute("role", "alert")
  root.textContent = "Overlay connection unavailable. Copy the current Browser Source URL from ShowRunner."
  console.error("Overlay connection unavailable. Copy the current Browser Source URL from ShowRunner.")
})

Object.assign(window, { showRunnerOverlayRuntime: runtime, showRunnerOverlayRegistry: registry })
