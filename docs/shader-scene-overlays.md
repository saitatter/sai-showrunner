# Shader Scene Overlays Plan

ShowRunner scene overlays should extend the existing OBS browser source model instead of introducing a second runtime. A scene is an overlay resource that can render DOM widgets, a WebGL shader layer, or both.

## Scene Contract V1

Scene resources use a small manifest:

```json
{
	"key": "stream-start",
	"name": "Stream Start",
	"runtime": "webgl-scene",
	"fragmentShader": "fragment.glsl",
	"duration": 300,
	"params": {
		"title": "Starting Soon",
		"accentColor": "#9146ff",
		"intensity": 0.8
	}
}
```

- `key` is the stable automation/OBS reference.
- `runtime` starts with `webgl-scene`; future runtimes can add DOM-only or Three.js modes.
- `fragmentShader` is a relative asset path beside the manifest.
- `params` is the live-editable state exposed to automation nodes and overlay widgets.

## Runtime Shape

- The OBS browser source loads `/overlays/{id}` like existing overlays.
- The scene layer mounts a full-canvas WebGL renderer behind regular DOM widgets.
- Shader params are pushed through the existing overlay websocket config/state channel.
- Saving a scene updates the live preview immediately, matching the current overlay editor model.

## Automation Integration

Automation nodes should add three actions:

- `scene.begin`: select scene key, target overlay, optional duration override.
- `scene.update`: patch params without restarting the shader timeline.
- `scene.end`: return the target overlay to idle/transparent scene state.

The node editor can represent these actions as time-aware nodes so scene changes can be aligned with alerts, sounds, OBS transitions, and chat events.

## MVP Boundaries

- No custom shader editor in the first runtime pass.
- No remote shader asset loading; shader paths stay inside the scene asset bundle.
- No persistence schema change until the scene resource type is implemented.
- Donation alerts and begin/end stream templates can use this runtime later, but are not part of the first shader PR.
