import { readFileSync, writeFileSync } from "node:fs"
import path from "node:path"

export function generateProtocol(root) {
  const schema = JSON.parse(readFileSync(path.join(root, "tools/overlay_registry/overlay-protocol.schema.json"), "utf8"))
  for (const [template, destination] of [
    ["protocol.ts.template", "libs/showrunner-overlay-core/src/generated/overlay-protocol.generated.ts"],
    ["protocol.dart.template", "packages/showrunner-flutter/lib/plugins/overlays/overlay_protocol.generated.dart"],
  ]) {
    const source = readFileSync(path.join(root, "tools/overlay_registry", template), "utf8")
    writeFileSync(path.join(root, destination), source.replace("__SCHEMA__", JSON.stringify(schema)))
  }
}
