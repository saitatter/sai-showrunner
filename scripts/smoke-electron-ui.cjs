const fs = require("node:fs")
const http = require("node:http")
const os = require("node:os")
const path = require("node:path")
const { spawn } = require("node:child_process")
const WebSocket = require("ws")

const rootDir = path.resolve(__dirname, "..")
const appEntry = path.join(rootDir, "packages", "showrunner", "dist", "dist-electron", "background.js")
const userDir = fs.mkdtempSync(path.join(os.tmpdir(), "showrunner-smoke-"))
const port = Number(process.env.SHOWRUNNER_SMOKE_CDP_PORT || 9229 + Math.floor(Math.random() * 500))
const timeoutMs = Number(process.env.SHOWRUNNER_SMOKE_TIMEOUT_MS || 45000)
const clickSelector =
	"button,a,[role='menuitem'],.p-menubar-item-link,.p-menuitem-link,.p-menu-item-link,.p-tieredmenu-item-link,.p-treenode-content,.docked-tab-head,.project-item,.project-category-header"

function fail(message) {
	console.error(message)
	process.exitCode = 1
}

function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms))
}

function httpJson(url) {
	return new Promise((resolve, reject) => {
		const req = http.get(url, (res) => {
			let body = ""
			res.setEncoding("utf8")
			res.on("data", (chunk) => {
				body += chunk
			})
			res.on("end", () => {
				try {
					resolve(JSON.parse(body))
				} catch (error) {
					reject(error)
				}
			})
		})
		req.on("error", reject)
		req.setTimeout(2500, () => {
			req.destroy(new Error(`Timed out fetching ${url}`))
		})
	})
}

async function waitForDevtoolsTarget() {
	const deadline = Date.now() + timeoutMs
	let lastError
	while (Date.now() < deadline) {
		try {
			const targets = await httpJson(`http://127.0.0.1:${port}/json/list`)
			const page = targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl)
			if (page) return page
		} catch (error) {
			lastError = error
		}
		await sleep(250)
	}
	throw new Error(`Electron DevTools target did not appear on port ${port}: ${lastError?.message ?? "timeout"}`)
}

function connectCdp(webSocketDebuggerUrl) {
	const socket = new WebSocket(webSocketDebuggerUrl)
	let nextId = 1
	const pending = new Map()

	socket.on("message", (data) => {
		const message = JSON.parse(String(data))
		if (!message.id || !pending.has(message.id)) return
		const { resolve, reject } = pending.get(message.id)
		pending.delete(message.id)
		if (message.error) reject(new Error(message.error.message))
		else resolve(message.result)
	})

	function send(method, params = {}) {
		const id = nextId++
		socket.send(JSON.stringify({ id, method, params }))
		return new Promise((resolve, reject) => {
			pending.set(id, { resolve, reject })
		})
	}

	return new Promise((resolve, reject) => {
		socket.once("open", () => resolve({ socket, send }))
		socket.once("error", reject)
	})
}

async function waitFor(send, expression, label, localTimeoutMs = 12000) {
	const deadline = Date.now() + localTimeoutMs
	let lastValue
	while (Date.now() < deadline) {
		const result = await evaluate(send, expression)
		lastValue = result
		if (result) return result
		await sleep(250)
	}
	const bodyText = await evaluate(send, `document.body?.innerText?.slice(0, 1200) || ""`).catch(() => "")
	throw new Error(`Timed out waiting for ${label}. Last value: ${JSON.stringify(lastValue)}\nBody excerpt: ${bodyText}`)
}

async function evaluate(send, expression) {
	const result = await send("Runtime.evaluate", {
		expression,
		awaitPromise: true,
		returnByValue: true,
	})
	if (result.exceptionDetails) {
		throw new Error(result.exceptionDetails.text || "Runtime.evaluate failed")
	}
	return result.result?.value
}

function visibleTextClickExpression(text) {
	return `
		(() => {
			const wanted = ${JSON.stringify(text)};
			const clickableSelector = ${JSON.stringify(clickSelector)};
			const elements = [...document.querySelectorAll(clickableSelector)];
			const matches = elements.filter((element) => {
				const rect = element.getBoundingClientRect();
				const style = getComputedStyle(element);
				const label = (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim();
				return style.visibility !== "hidden" && style.display !== "none" && label.includes(wanted);
			});
			const target = matches.find((element) => {
				const rect = element.getBoundingClientRect();
				return rect.width > 0 && rect.height > 0 && element.matches(clickableSelector);
			}) ?? matches.find((element) => {
				const label = (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim();
				return label === wanted && element.matches(clickableSelector);
			}) ?? matches.find((element) => {
				const rect = element.getBoundingClientRect();
				return rect.width > 0 && rect.height > 0;
			}) ?? matches[0];
			if (!target) return false;
			target.dispatchEvent(new MouseEvent("pointerover", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("mouseover", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("pointerup", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
			return true;
		})()
	`
}

function visibleTextTargetExpression(text) {
	return `
		(() => {
			const wanted = ${JSON.stringify(text)};
			const elements = [...document.querySelectorAll(${JSON.stringify(clickSelector)})];
			const matches = elements
				.map((element) => {
					const rect = element.getBoundingClientRect();
					const style = getComputedStyle(element);
					const label = (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim();
					return { element, rect, label, visible: style.visibility !== "hidden" && style.display !== "none" && rect.width > 0 && rect.height > 0 };
				})
				.filter((item) => item.visible && item.label.includes(wanted));
			const target = matches.find((item) => item.label === wanted) ?? matches[0];
			if (!target) return undefined;
			return {
				x: target.rect.left + target.rect.width / 2,
				y: target.rect.top + target.rect.height / 2,
				label: target.label,
				className: String(target.element.className || ""),
			};
		})()
	`
}

async function clickText(send, text) {
	const target = await waitFor(send, visibleTextTargetExpression(text), `visible clickable text ${text}`, 8000).catch(() => undefined)
	if (target) {
		await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: target.x, y: target.y })
		await send("Input.dispatchMouseEvent", { type: "mousePressed", x: target.x, y: target.y, button: "left", clickCount: 1 })
		await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: target.x, y: target.y, button: "left", clickCount: 1 })
		await sleep(350)
		return
	}

	try {
		await waitFor(send, visibleTextClickExpression(text), `clickable text ${text}`, 1500)
	} catch (error) {
		const candidates = await evaluate(send, `
			[...document.querySelectorAll(${JSON.stringify(clickSelector)})]
				.map((element) => ({
					text: (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim(),
					className: element.className,
					role: element.getAttribute("role"),
					rect: (() => {
						const rect = element.getBoundingClientRect();
						return { width: rect.width, height: rect.height };
					})(),
				}))
				.filter((item) => item.text)
				.slice(0, 40)
		`)
		throw new Error(`${error.message}\nVisible clickable candidates: ${JSON.stringify(candidates)}`)
	}
	await sleep(350)
}

async function hoverText(send, text) {
	const target = await waitFor(send, visibleTextTargetExpression(text), `visible hover target ${text}`, 8000)
	await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: target.x, y: target.y })
	await sleep(650)
}

async function clickDockTab(send, text) {
	await waitFor(send, `
		(() => {
			const wanted = ${JSON.stringify(text)};
			const target = [...document.querySelectorAll(".docked-tab-head")].find((element) => {
				const rect = element.getBoundingClientRect();
				const label = (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim();
				return rect.width > 0 && rect.height > 0 && label.includes(wanted);
			});
			if (!target) return false;
			target.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true, view: window }));
			target.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
			return true;
		})()
	`, `dock tab ${text}`, 8000)
	await sleep(350)
}

async function assertNoRuntimeError(send) {
	const text = await evaluate(send, `document.body?.innerText || ""`)
	const forbidden = [
		"Automation editor failed",
		"TypeError:",
		"ReferenceError:",
		"Cannot read properties of undefined",
	]
	for (const marker of forbidden) {
		if (text.includes(marker)) throw new Error(`Renderer contains runtime error marker: ${marker}`)
	}
}

async function main() {
	if (!fs.existsSync(appEntry)) {
		throw new Error(`Missing built Electron entry: ${appEntry}. Run corepack yarn check first.`)
	}

	fs.writeFileSync(path.join(userDir, "start-info.yaml"), "lastVer: 0.0.0\n")

	const electronPath = require("electron")
	const electronEnv = {
		...process.env,
		IS_TEST: "1",
		SHOWRUNNER_USER_DIR: userDir,
		ELECTRON_ENABLE_LOGGING: "0",
	}
	delete electronEnv.ELECTRON_RUN_AS_NODE

	const child = spawn(electronPath, [
		".",
		`--remote-debugging-port=${port}`,
		"--disable-gpu",
	], {
		cwd: path.join(rootDir, "packages", "showrunner"),
		env: electronEnv,
		stdio: ["ignore", "pipe", "pipe"],
		windowsHide: true,
	})

	let stderr = ""
	let stdout = ""
	let exited = false
	let exitCode
	child.stdout.on("data", (chunk) => {
		stdout += String(chunk)
	})
	child.stderr.on("data", (chunk) => {
		stderr += String(chunk)
	})
	child.on("exit", (code) => {
		exited = true
		exitCode = code
	})

	let cdp
	let failed = false
	try {
		const target = await waitForDevtoolsTarget()
		if (exited) throw new Error(`Electron exited before smoke could run with code ${exitCode}`)
		cdp = await connectCdp(target.webSocketDebuggerUrl)
		await cdp.send("Runtime.enable")
		await waitFor(cdp.send, `document.body && document.body.innerText.includes("ShowRunner")`, "main ShowRunner shell", 20000)
		await assertNoRuntimeError(cdp.send)

		await clickText(cdp.send, "File")
		await clickText(cdp.send, "Settings")
		await clickDockTab(cdp.send, "Settings")
		await waitFor(cdp.send, `Boolean(document.querySelector(".settings-page"))`, "Settings page")
		await assertNoRuntimeError(cdp.send)

		await clickText(cdp.send, "Help")
		await clickText(cdp.send, "Updates")
		await clickDockTab(cdp.send, "Updates")
		await waitFor(cdp.send, `Boolean(document.querySelector(".updates-page"))`, "Updates page")
		await assertNoRuntimeError(cdp.send)

		await clickText(cdp.send, "File")
		await hoverText(cdp.send, "New Automation From Starter")
		await clickText(cdp.send, "Paid Event -> Add to Alerts Queue")
		await waitFor(cdp.send, `Boolean(document.querySelector(".node-automation"))`, "automation graph editor")
		await waitFor(cdp.send, `Boolean(document.querySelector(".node-automation__canvas-controls"))`, "automation graph controls")
		await assertNoRuntimeError(cdp.send)

		await clickText(cdp.send, "Integrations")
		await clickText(cdp.send, "Production & Overlays")
		await clickText(cdp.send, "OBS")
		await waitFor(cdp.send, `document.body.innerText.includes("INTEGRATION PLUGIN") && document.body.innerText.includes("OBS")`, "Integrations plugin details")
		await assertNoRuntimeError(cdp.send)

		console.log(`Electron UI smoke passed with isolated user dir ${userDir}`)
	} catch (error) {
		failed = true
		throw error
	} finally {
		cdp?.socket?.close()
		child.kill()
		await sleep(250)
		if (!child.killed) child.kill("SIGKILL")
		if (failed || process.exitCode) {
			console.error([stdout, stderr].filter(Boolean).join("\n"))
		} else {
			fs.rmSync(userDir, { recursive: true, force: true })
		}
	}
}

main().catch((error) => {
	fail(error.stack || error.message)
})
