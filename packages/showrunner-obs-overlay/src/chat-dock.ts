import "./chat-dock.css"

type Message = { identity: string; platform: string; viewerName: string; message: string; isOwner: boolean; deleted: boolean }
type Emote = { name: string; text: string }
type Completion = { text: string; label: string; kind: string }
const element = <T extends HTMLElement>(id: string) => document.getElementById(id) as T
const history = element<HTMLElement>("messages")
const status = element<HTMLElement>("status")
const input = element<HTMLInputElement>("message")
const platform = element<HTMLSelectElement>("platform")
const filter = element<HTMLSelectElement>("filter")
const form = element<HTMLFormElement>("composer")
const token = location.hash.slice(1)
let messages: Message[] = []
let emotes: Emote[] = []
let signature = ""
let completions: Record<string, Completion[]> = {}
let candidates: Completion[] = []
let selectedCompletion = 0
let pausedIdentities: Set<string> | undefined
let userIdentity: string | undefined
const userKey = (message: Message) => `${message.platform}:${(message as Message & { viewerId?: string }).viewerId ?? ""}`

async function request(path: string, body?: unknown) {
  const response = await fetch(path, { method: body ? "POST" : "GET", headers: { "x-showrunner-chat": token, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined })
  if (!response.ok) throw new Error(response.status === 401 ? "Re-copy the OBS dock URL from ShowRunner Chat." : "Chat operation failed. Check the connection and permissions in ShowRunner.")
  return response.json()
}
function render() {
  const atBottom = history.scrollHeight - history.scrollTop - history.clientHeight < 50
  history.replaceChildren()
  for (const message of messages.filter(m => (!filter.value || m.platform === filter.value) && (!pausedIdentities || pausedIdentities.has(m.identity)) && (!userIdentity || userKey(m) === userIdentity))) {
    const row = document.createElement("article")
    const title = document.createElement("strong")
    title.textContent = `${message.platform} · ${message.viewerName}`
    const text = document.createElement("p")
    text.textContent = message.deleted ? "Message deleted" : message.message
    const actions = document.createElement("select")
    actions.setAttribute("aria-label", "Message actions")
    for (const [value, label] of [["", "Actions"], ["reply", "Reply"], ["copy", "Copy message"], ["user", "Show messages from user"], ...(!message.deleted ? [["deleteMessage", "Delete message"]] : []), ...(!message.isOwner ? [["timeout", "Timeout 60s"], ["ban", "Ban user"], ...(message.platform === "twitch" ? [["unban", "Unban user"]] : [])] : [])]) {
      const option = document.createElement("option"); option.value = value; option.textContent = label; actions.append(option)
    }
    actions.addEventListener("change", async () => {
      const action = actions.value; actions.value = ""
      if (action === "reply") { platform.value = message.platform; input.value = `@${message.viewerName} `; input.focus(); return }
      if (action === "user") { userIdentity = userKey(message); render(); return }
      if (action === "copy") {
        try { await navigator.clipboard.writeText(message.message); status.textContent = "Message copied." }
        catch { status.textContent = "Clipboard unavailable. Select and copy the message text." }
        return
      }
      if (!action || !confirm(`${actions.querySelector(`option[value="${action}"]`)?.textContent}: ${message.viewerName}?`)) return
      try { await request("/api/action", { identity: message.identity, action }); status.textContent = "Action sent." } catch (error) { status.textContent = String(error) }
    })
    row.append(title, actions, text); history.append(row)
  }
  if (atBottom) history.scrollTop = history.scrollHeight
}
filter.addEventListener("change", () => { userIdentity = undefined; render() })
function insertCompletion(index: number) {
  const completion = candidates[index]
  if (!completion) return
  const cursor = input.selectionStart ?? input.value.length
  const word = input.value.slice(0, cursor).split(/\s/).at(-1) ?? ""
  input.setRangeText(`${completion.text} `, cursor - word.length, cursor, "end")
  candidates = []; element("emotes").replaceChildren(); input.focus()
}
function suggest(reset = true) {
  if (reset) selectedCompletion = 0
  const suggestions = element("emotes"); suggestions.replaceChildren()
  const cursor = input.selectionStart ?? input.value.length
  const before = input.value.slice(0, cursor)
  const word = before.split(/\s/).at(-1) ?? ""
  const first = !/\s/.test(before.trimStart())
  const available = completions[platform.value] ?? emotes
    .filter(e => platform.value === "twitch" || e.name.startsWith(":"))
    .map(e => ({ ...e, label: e.name, kind: "emote" }))
  candidates = word && (word.length >= 2 || word === "!" || word === "/")
    ? available.filter(e => (e.kind === "emote" || first) && (e.kind === "emote" ? e.label : e.text).toLowerCase().startsWith(word.toLowerCase())).slice(0, 12) : []
  selectedCompletion = candidates.length ? (selectedCompletion + candidates.length) % candidates.length : 0
  for (const [index, item] of candidates.entries()) {
    const button = document.createElement("button"); button.type = "button"; button.textContent = item.label
    button.setAttribute("aria-pressed", String(index === selectedCompletion))
    button.addEventListener("click", () => insertCompletion(index)); suggestions.append(button)
  }
}
input.addEventListener("input", () => suggest())
platform.addEventListener("change", () => suggest())
input.addEventListener("keydown", event => {
  if (!candidates.length) return
  if (event.key === "Tab" || event.key === "Enter") { event.preventDefault(); insertCompletion(selectedCompletion) }
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault(); selectedCompletion += event.key === "ArrowDown" ? 1 : -1; suggest(false)
  }
})
form.addEventListener("submit", async event => {
  event.preventDefault()
  const button = form.querySelector("button")!; button.disabled = true
  const sentText = input.value
  try {
    switch (sentText.trim()) {
      case "/clear": await request("/api/clear", {}); messages = []; signature = ""; render(); status.textContent = "Local history cleared."; break
      case "/pause": pausedIdentities = new Set(messages.map(m => m.identity)); render(); status.textContent = "View paused. Use /resume to show incoming messages."; break
      case "/resume": pausedIdentities = undefined; render(); status.textContent = "View resumed."; break
      default: await request("/api/send", { platform: platform.value, message: sentText }); status.textContent = "Message sent."
    }
    if (input.value === sentText) input.value = ""
    suggest()
  }
  catch (error) { status.textContent = String(error) }
  finally { button.disabled = false }
})
async function poll() {
  try {
    const snapshot = await request("/api/chat") as { messages: Message[]; emotes: Emote[]; completions?: Record<string, Completion[]> }
    const next = JSON.stringify(snapshot.messages)
    emotes = snapshot.emotes
    completions = snapshot.completions ?? {}
    if (next !== signature) { signature = next; messages = snapshot.messages; render() }
    if (status.textContent?.startsWith("Error:")) status.textContent = "Connected."
  } catch (error) { status.textContent = String(error) }
  setTimeout(poll, 1000)
}
void poll()
