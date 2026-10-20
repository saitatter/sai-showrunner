import { execFileSync } from "node:child_process"
import { createHash } from "node:crypto"
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname, extname, posix, resolve, relative, isAbsolute } from "node:path"
import { arch, platform, release, version } from "node:os"
import { fileURLToPath } from "node:url"

// Source inventory, not a parser or a runtime leak detector. Keep raw evidence
// outside maintained documentation; use the same command after structural work.
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const run = (command, args) => execFileSync(command, args, { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 }).trim()
const destination = resolve(root, process.argv[2] ?? ".tmp/audit-global/inventory.json")
const outputPath = relative(resolve(root, ".tmp"), destination)
if (!outputPath || isAbsolute(outputPath) || outputPath === ".." || outputPath.startsWith("../") || outputPath.startsWith("..\\")) {
  throw new Error("Audit output must be inside repository .tmp")
}
const tracked = new Set(run("git", ["ls-files"]).split(/\r?\n/))
const candidates = run("rg", ["--files", "packages", "libs", "plugins"]).split(/\r?\n/).map(p => p.replaceAll("\\", "/"))
const files = candidates
  .filter(p => tracked.has(p) && /\.(dart|[cm]?[jt]sx?|cpp|h)$/.test(p)).sort()
const sources = new Map(files.map(p => [p, readFileSync(resolve(root, p), "utf8")]))
const domains = {}
const sites = { parts: [], modules: [], manifests: [], registrations: [], handlers: [], listeners: [], timers: [], servers: [] }
const patterns = {
  parts: /^\s*part\s+['"]([^'"]+)['"]/gm,
  modules: /\bimplements\s+DartPluginModule\b/g,
  manifests: /\bDartPluginManifest\s*\(/g,
  registrations: /\bregistry\s*\.\.?(?:register|registerModule)\s*\(/g,
  handlers: /\b(?:ActionSpec|TriggerSpec|addRequestHandler|addWebSocketHandler)\s*(?:<[^;\n]+>)?\s*\(/g,
  listeners: /\.listen\s*\(|\baddListener\s*\(|\baddEventListener\s*\(/g,
  timers: /\bTimer(?:\.periodic)?\s*\(|\bset(?:Interval|Timeout)\s*\(/g,
  servers: /\b(?:HttpServer|ServerSocket|RawDatagramSocket)\.bind\s*\(/g,
}
const partOwners = new Map()
for (const [file, source] of sources) {
  const segments = file.split("/")
  const domain = segments.slice(0, ["lib", "test", "integration_test"].includes(segments[2]) ? (segments[3] === "plugins" || segments[3] === "features" ? 5 : 4) : 3).join("/")
  const row = domains[domain] ??= { files: 0, lines: 0 }
  row.files++; row.lines += source.split(/\r?\n/).length
  for (const [kind, pattern] of Object.entries(patterns)) {
    for (const match of source.matchAll(pattern)) {
      sites[kind].push({ file, line: source.slice(0, match.index).split("\n").length })
      if (kind === "parts") partOwners.set(posix.normalize(posix.join(posix.dirname(file), match[1])), file)
    }
  }
}
function target(file, uri) {
  let candidate
  if (uri.startsWith("package:showrunner_flutter/")) candidate = `packages/showrunner-flutter/lib/${uri.slice(27)}`
  else if (uri.startsWith(".")) candidate = posix.normalize(posix.join(posix.dirname(file), uri))
  else return null
  const variants = [candidate, candidate.replace(/\.js$/, ".ts"), ...[".ts", ".tsx", ".mjs", ".dart", "/index.ts"].map(s => candidate + s)]
  return variants.find(p => sources.has(p)) ?? null
}
const graph = new Map()
for (const [file, source] of sources) {
  const owner = partOwners.get(file) ?? file
  if (!graph.has(owner)) graph.set(owner, new Set())
  const imports = file.endsWith(".dart")
    ? [...source.matchAll(/^\s*(?:import|export)\s+['"]([^'"]+)['"]/gm)].map(m => m[1])
    : [...source.matchAll(/(?:\bfrom\s*|\bimport\s*)['"]([^'"]+)['"]/g)].map(m => m[1])
  for (const uri of imports) {
    const found = target(file, uri)
    const dependency = partOwners.get(found) ?? found
    if (dependency && dependency !== owner) graph.get(owner).add(dependency)
  }
}
// Tarjan strongly connected components, with Dart part files collapsed into
// their owning library. Package aliases/conditional imports are not resolved.
let nextIndex = 0
const indices = new Map(), low = new Map(), stack = [], active = new Set(), cycles = []
function visit(node) {
  indices.set(node, nextIndex); low.set(node, nextIndex++)
  stack.push(node); active.add(node)
  for (const dependency of graph.get(node) ?? []) {
    if (!indices.has(dependency)) { visit(dependency); low.set(node, Math.min(low.get(node), low.get(dependency))) }
    else if (active.has(dependency)) low.set(node, Math.min(low.get(node), indices.get(dependency)))
  }
  if (low.get(node) !== indices.get(node)) return
  const component = []
  let member
  do { member = stack.pop(); active.delete(member); component.push(member) } while (member !== node)
  if (component.length > 1) cycles.push(component.sort())
}
for (const node of [...graph.keys()].sort()) if (!indices.has(node)) visit(node)
const locks = ["yarn.lock", "packages/showrunner-flutter/pubspec.lock"]
const flutter = JSON.parse(platform() === "win32"
  ? run("powershell.exe", ["-NoProfile", "-Command", "flutter --version --machine; exit $LASTEXITCODE"])
  : run("flutter", ["--version", "--machine"]))
const report = {
  schemaVersion: 1,
  head: run("git", ["rev-parse", "HEAD"]),
  branch: run("git", ["branch", "--show-current"]),
  status: run("git", ["status", "--porcelain=v1"]).split(/\r?\n/).filter(Boolean),
  environment: { platform: platform(), release: release(), version: version(), arch: arch(), node: process.version, yarn: run(process.execPath, [".yarn/releases/yarn-4.1.0.cjs", "--version"]), flutter },
  lockfiles: Object.fromEntries(locks.map(file => [file, createHash("sha256").update(readFileSync(resolve(root, file))).digest("hex")])),
  manifests: candidates.filter(file => tracked.has(file) && /(?:package\.json|pubspec\.yaml)$/.test(file)).sort(),
  inventory: { files: files.length, domains, extensions: Object.fromEntries([...new Set(files.map(extname))].sort().map(extension => [extension, files.filter(p => extname(p) === extension).length])) },
  largest: files.map(file => ({ file, lines: sources.get(file).split(/\r?\n/).length })).sort((a, b) => b.lines - a.lines || a.file.localeCompare(b.file)).slice(0, 20),
  staticSites: sites,
  partLibraries: new Set(sites.parts.map(site => site.file)).size,
  importGraph: { libraries: graph.size, edges: [...graph.values()].reduce((sum, edges) => sum + edges.size, 0), cycles: cycles.sort((a, b) => a[0].localeCompare(b[0])) },
  limitations: "Lexical inventory includes tests and generated sources; static sites are candidates, not live resource counts. Import graph resolves relative and showrunner_flutter Dart imports only, collapses parts, and omits aliases, native includes and conditional imports.",
}
mkdirSync(dirname(destination), { recursive: true })
writeFileSync(destination, JSON.stringify(report, null, 2) + "\n")
console.log(JSON.stringify({ output: relative(root, destination), files: files.length, staticSites: Object.fromEntries(Object.entries(sites).map(([key, value]) => [key, value.length])), cycles: cycles.length }))
