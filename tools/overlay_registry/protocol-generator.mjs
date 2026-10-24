import { readFileSync, writeFileSync } from "node:fs"
import path from "node:path"

export function generateProtocol(root) {
  const schema = JSON.parse(readFileSync(path.join(root, "tools/overlay_registry/overlay-protocol.schema.json"), "utf8"))
  for (const [template, destination] of [
    ["protocol.ts.template", "libs/showrunner-overlay-core/src/generated/overlay-protocol.generated.ts"],
    ["protocol.dart.template", "packages/showrunner-flutter/lib/plugins/overlays/overlay_protocol.generated.dart"],
    ["protocol.dart.template", "packages/showrunner-flutter/lib/plugins/remote/remote_protocol.generated.dart"],
  ]) {
    const source = readFileSync(path.join(root, "tools/overlay_registry", template), "utf8")
    const generated = source.replace("__SCHEMA__", JSON.stringify(schema))
      .replace("__RENDER_LIMIT_TYPES__", Object.keys(schema["x-renderLimits"]).map(key => `${key}:number`).join(";"))
    writeFileSync(path.join(root, destination), destination.includes("/remote/")
      ? generated.replaceAll("decodeOverlayWire", "decodeRemoteWire").replaceAll("encodeOverlayWire", "encodeRemoteWire")
      : generated)
  }
}
