const fs = require("node:fs")
const http = require("node:http")
const os = require("node:os")
const path = require("node:path")
const { spawn } = require("node:child_process")

const repositoryRoot = path.resolve(__dirname, "..", "..")
const referenceRoot = path.join(repositoryRoot, ".tmp", "main-reference")
const appRoot = path.join(referenceRoot, "packages", "showrunner")
const appEntry = path.join(appRoot, "dist", "dist-electron", "background.js")
const outputRoot = path.join(repositoryRoot, "test", "reference", "main")
const electronPath = require(path.join(referenceRoot, "node_modules", "electron"))
const userDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "showrunner-reference-"))
const port = 9229 + Math.floor(Math.random() * 400)

function sleep(milliseconds) {
	return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

function httpJson(url) {
	return new Promise((resolve, reject) => {
		const request = http.get(url, (response) => {
			let body = ""
			response.setEncoding("utf8")
			response.on("data", (chunk) => (body += chunk))
			response.on("end", () => {
				try {
					resolve(JSON.parse(body))
				} catch (error) {
					reject(error)
				}
			})
		})
		request.on("error", reject)
		request.setTimeout(2500, () => request.destroy(new Error("CDP request timed out")))
	})
}

async function waitForTarget() {
	const deadline = Date.now() + 30000
	while (Date.now() < deadline) {
		try {
			const targets = await httpJson(`http://127.0.0.1:${port}/json/list`)
			const target = targets.find((item) => item.type === "page" && item.webSocketDebuggerUrl)
			if (target) return target
		} catch (_) {
			// Electron is still starting.
		}
		await sleep(250)
	}
	throw new Error("Electron DevTools target did not appear")
}

function connectCdp(webSocketDebuggerUrl) {
	const WebSocket = require(path.join(referenceRoot, "node_modules", "ws"))
	const socket = new WebSocket(webSocketDebuggerUrl)
	let nextId = 1
	const pending = new Map()

	socket.on("message", (data) => {
		const message = JSON.parse(String(data))
		if (!message.id || !pending.has(message.id)) return
		const request = pending.get(message.id)
		pending.delete(message.id)
		if (message.error) request.reject(new Error(message.error.message))
		else request.resolve(message.result)
	})

	function send(method, params = {}) {
		const id = nextId++
		socket.send(JSON.stringify({ id, method, params }))
		return new Promise((resolve, reject) => pending.set(id, { resolve, reject }))
	}

	return new Promise((resolve, reject) => {
		socket.once("open", () => resolve({ socket, send }))
		socket.once("error", reject)
	})
}

async function evaluate(send, expression) {
	const result = await send("Runtime.evaluate", {
		expression,
		awaitPromise: true,
		returnByValue: true,
	})
	if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "CDP evaluation failed")
	return result.result?.value
}

async function waitFor(send, expression, label) {
	const deadline = Date.now() + 12000
	while (Date.now() < deadline) {
		if (await evaluate(send, expression)) return
		await sleep(250)
	}
	throw new Error(`Timed out waiting for ${label}`)
}

async function clickText(send, text) {
	const expression = `
		(() => {
			const wanted = ${JSON.stringify(text)};
			const selectors = "button,a,[role='menuitem'],.p-menubar-item-link,.p-menuitem-link,.p-menu-item-link,.p-tieredmenu-item-link,.p-treenode-content,.docked-tab-head,.project-item,.project-category-header";
			const matches = [...document.querySelectorAll(selectors)].map((element) => {
				const rect = element.getBoundingClientRect();
				const style = getComputedStyle(element);
				const label = (element.innerText || element.textContent || '').replace(/\\s+/g, ' ').trim();
			return { element, rect, label, visible: rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' };
			}).filter((item) => item.visible && item.label.includes(wanted));
			const target = matches.find((item) => item.label === wanted) || matches[0];
			if (!target) return null;
			return { x: target.rect.left + target.rect.width / 2, y: target.rect.top + target.rect.height / 2 };
		})()
	`
	const deadline = Date.now() + 12000
	let target
	while (Date.now() < deadline) {
		target = await evaluate(send, expression)
		if (target) break
		await sleep(250)
	}
	if (!target) {
		const body = await evaluate(send, `document.body?.innerText?.slice(0, 1600) || ''`)
		throw new Error(`Timed out waiting for clickable text ${text}. Body: ${body}`)
	}
	await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: target.x, y: target.y })
	await send("Input.dispatchMouseEvent", { type: "mousePressed", x: target.x, y: target.y, button: "left", clickCount: 1 })
	await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: target.x, y: target.y, button: "left", clickCount: 1 })
	await sleep(400)
}

async function hoverText(send, text) {
	const expression = `
		(() => {
			const wanted = ${JSON.stringify(text)};
			const selectors = "button,a,[role='menuitem'],.p-menubar-item-link,.p-menuitem-link,.p-menu-item-link,.p-tieredmenu-item-link,.p-treenode-content,.docked-tab-head,.project-item,.project-category-header";
			const matches = [...document.querySelectorAll(selectors)].map((element) => {
				const rect = element.getBoundingClientRect();
				const style = getComputedStyle(element);
				const label = (element.innerText || element.textContent || '').replace(/\\s+/g, ' ').trim();
				return { rect, label, visible: rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' };
			}).filter((item) => item.visible && item.label.includes(wanted));
			const target = matches.find((item) => item.label === wanted) || matches[0];
			if (!target) return null;
			return { x: target.rect.left + target.rect.width / 2, y: target.rect.top + target.rect.height / 2 };
		})()
	`
	const deadline = Date.now() + 12000
	let target
	while (Date.now() < deadline) {
		target = await evaluate(send, expression)
		if (target) break
		await sleep(250)
	}
	if (!target) throw new Error(`Timed out waiting for hover target ${text}`)
	await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: target.x, y: target.y })
	await sleep(650)
}

async function capture(send, fileName) {
	const image = await send("Page.captureScreenshot", { format: "png", fromSurface: true })
	fs.mkdirSync(outputRoot, { recursive: true })
	fs.writeFileSync(path.join(outputRoot, fileName), Buffer.from(image.data, "base64"))
	console.log(`Captured ${fileName}`)
}

async function main() {
	if (!fs.existsSync(appEntry)) throw new Error(`Missing Electron build: ${appEntry}`)
	fs.writeFileSync(path.join(userDirectory, "start-info.yaml"), "lastVer: 0.0.0\n")
	const environment = {
		...process.env,
		IS_TEST: "1",
		SHOWRUNNER_USER_DIR: userDirectory,
		ELECTRON_ENABLE_LOGGING: "0",
		ELECTRON_DISABLE_SECURITY_WARNINGS: "true",
	}
	delete environment.ELECTRON_RUN_AS_NODE

	const child = spawn(electronPath, [".", `--remote-debugging-port=${port}`, "--disable-gpu"], {
		cwd: appRoot,
		env: environment,
		stdio: ["ignore", "ignore", "ignore"],
		windowsHide: true,
	})
	let cdp
	try {
		const target = await waitForTarget()
		cdp = await connectCdp(target.webSocketDebuggerUrl)
		await cdp.send("Runtime.enable")
		await cdp.send("Page.enable")
		await cdp.send("Emulation.setDeviceMetricsOverride", {
			width: 1440,
			height: 900,
			deviceScaleFactor: 1,
			mobile: false,
		})
		await waitFor(
			cdp.send,
			`document.body && document.body.innerText.includes("Profiles") && !document.body.innerText.includes("Loading ShowRunner")`,
			"loaded ShowRunner shell",
		)

		await capture(cdp.send, "app-empty.png")
		await clickText(cdp.send, "File")
		await clickText(cdp.send, "Settings")
		await clickText(cdp.send, "Settings")
		await waitFor(cdp.send, `Boolean(document.querySelector('.settings-page'))`, "settings")
		await capture(cdp.send, "settings.png")

		await clickText(cdp.send, "Help")
		await clickText(cdp.send, "Updates")
		await clickText(cdp.send, "Updates")
		await waitFor(cdp.send, `Boolean(document.querySelector('.updates-page'))`, "updates")
		await capture(cdp.send, "updater.png")

		await clickText(cdp.send, "File")
		await hoverText(cdp.send, "New Automation From Starter")
		await clickText(cdp.send, "Paid Event -> Add to Alerts Queue")
		await waitFor(cdp.send, `Boolean(document.querySelector('.node-automation'))`, "automation editor")
		await capture(cdp.send, "automation-editor-complex.png")

		await clickText(cdp.send, "Integrations")
		await waitFor(cdp.send, `document.body.innerText.includes('Integrations')`, "integrations")
		await capture(cdp.send, "integrations.png")
		await clickText(cdp.send, "Production & Overlays")
		if (await evaluate(cdp.send, `document.body.innerText.includes('OBS')`)) {
			await clickText(cdp.send, "OBS")
			await waitFor(cdp.send, `document.body.innerText.includes('OBS')`, "OBS workspace")
			await capture(cdp.send, "obs-workspace.png")
		} else {
			console.log("Skipped OBS capture: the frozen reference build does not expose an OBS catalog entry")
		}

		for (const [label, fileName] of [
			["Queues", "queues.png"],
			["Variables", "variables.png"],
			["Viewer Variables", "viewer-variables.png"],
		]) {
			await clickText(cdp.send, label)
			await capture(cdp.send, fileName)
		}
		if (await evaluate(cdp.send, `document.body.innerText.includes('Tools')`)) {
			await clickText(cdp.send, "Tools")
			for (const [label, fileName] of [
				["Diagnostics", "diagnostics.png"],
				["Logs", "logs.png"],
				["About", "about.png"],
			]) {
				await clickText(cdp.send, label)
				await capture(cdp.send, fileName)
			}
		} else {
			console.log("Skipped Tools captures: the frozen reference build does not expose a Tools group")
		}
	} finally {
		cdp?.socket?.close()
		if (!child.killed) child.kill()
		for (let attempt = 0; attempt < 8; attempt += 1) {
			try {
				fs.rmSync(userDirectory, { recursive: true, force: true })
				break
			} catch (error) {
				if (attempt === 7) throw error
				await sleep(250)
			}
		}
	}
}

main().catch((error) => {
	console.error(error.stack || error.message)
	process.exitCode = 1
})
