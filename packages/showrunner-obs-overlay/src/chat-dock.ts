import "./chat-dock.css"

type Message = { identity: string; platform: string; viewerName: string; message: string; isOwner: boolean; deleted: boolean; parts?: {text:string; imageUrl?:string}[]; highlighted?: boolean; time?: string; isModerator?: boolean }
type FeedEvent = { eventId: string; eventType: string; platform: string; viewerId: string; viewerName: string; message: string; time: string }
type ConfiguredAction = { id: string; label: string; scope: string; platforms: string[]; icon: string; color: string }
let configuredActions: ConfiguredAction[] = []
let events: FeedEvent[] = []
let pausedEventIds: Set<string> | undefined
type Emote = { name: string; text: string }
type Preferences = { fontSize: number; font: string; timestamps: boolean; newestFirst: boolean; alternatingRows: boolean; platformIcons: boolean; roleBadges: boolean }
let preferences: Preferences = { fontSize: 14, font: "system", timestamps: false, newestFirst: false, alternatingRows: false, platformIcons: true, roleBadges: true }
let storedPreferences: Record<string, unknown> | undefined
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
  const globals = element("global-actions"); globals.replaceChildren()
  for (const action of configuredActions.filter(a => a.scope === "global" && a.platforms.includes(platform.value))) {
    const button = document.createElement("button"); button.type = "button"; button.textContent = action.label
    button.dataset.color = action.color; button.title = `Run ${action.label}`
    button.addEventListener("click", async () => { button.disabled = true
      try { await request("/api/configured-action", {id:action.id, platform:platform.value}); status.textContent = "Action queued." }
      catch (error) { status.textContent = String(error) } finally { button.disabled = false }
    }); globals.append(button)
  }
  history.style.fontSize = `${preferences.fontSize}px`
  history.style.fontFamily = preferences.font === "system" ? "system-ui, sans-serif" : preferences.font
  history.classList.toggle("alternating", preferences.alternatingRows)
  if (element<HTMLSelectElement>("view").value === "events") {
    const visible = events.filter(e => (!filter.value || e.platform === filter.value) && (!pausedEventIds || pausedEventIds.has(e.eventId)) && (!userIdentity || `${e.platform}:${e.viewerId}` === userIdentity))
    if (preferences.newestFirst) visible.reverse()
    for (const event of visible) {
      const row = document.createElement("article"), title = document.createElement("strong"), text = document.createElement("p")
      title.textContent = `${event.platform} - ${event.eventType} - ${event.viewerName}`; text.textContent = event.message
      row.append(title, text)
      for (const action of configuredActions.filter(a => a.scope === "event" && a.platforms.includes(event.platform))) {
        const button = document.createElement("button"); button.type = "button"; button.textContent = action.label; button.dataset.color = action.color
        button.addEventListener("click", async () => { button.disabled = true
          try { await request("/api/configured-action", {id:action.id, platform:event.platform, eventId:event.eventId}); status.textContent = "Action queued." }
          catch (error) { status.textContent = String(error) } finally { button.disabled = false }
        }); row.append(button)
      }
      history.append(row)
    }
    return
  }
  const visible = messages.filter(m => (!filter.value || m.platform === filter.value) && (!pausedIdentities || pausedIdentities.has(m.identity)) && (!userIdentity || userKey(m) === userIdentity))
  if (preferences.newestFirst) visible.reverse()
  for (const message of visible) {
    const row = document.createElement("article")
    row.classList.toggle("highlighted", message.highlighted === true)
    const title = document.createElement("strong")
    title.textContent = `${preferences.timestamps && message.time ? new Date(message.time).toLocaleTimeString() + " " : ""}${preferences.platformIcons ? message.platform + " - " : ""}${message.viewerName}${preferences.roleBadges ? message.isOwner ? " - owner" : message.isModerator ? " - moderator" : "" : ""}`
    const text = document.createElement("p")
    if (message.deleted) text.textContent = "Message deleted"
    else if (message.parts) {
      for (const part of message.parts) {
        let url: URL | undefined
        try { if (part.imageUrl) url = new URL(part.imageUrl) } catch { /* text fallback */ }
        if (url && url.protocol === "https:" && !url.username && !url.password && (!url.port || url.port === "443") &&
            ["static-cdn.jtvnw.net", "cdn.betterttv.net", "cdn.frankerfacez.com", "cdn.7tv.app", "cdn.7tv.io"].includes(url.hostname)) {
          const image = document.createElement("img"); image.src = url.href; image.alt = part.text; image.title = part.text
          image.referrerPolicy = "no-referrer"; image.className = "emote"
          image.addEventListener("error", () => image.replaceWith(document.createTextNode(part.text)), {once:true})
          text.append(image)
        } else text.append(document.createTextNode(part.text))
      }
    } else text.textContent = message.message
    const actions = document.createElement("select")
    actions.setAttribute("aria-label", "Message actions")
    for (const [value, label] of [["", "Actions"], ["reply", "Reply"], ["copy", "Copy message"], ["user", "Show messages from user"], ...(!message.deleted ? [["deleteMessage", "Delete message"]] : []), ...(!message.isOwner ? [["timeout", "Timeout 60s"], ["ban", "Ban user"], ...(message.platform === "twitch" ? [["unban", "Unban user"]] : [])] : [])]) {
      const option = document.createElement("option"); option.value = value; option.textContent = label; actions.append(option)
    }
    for (const action of configuredActions.filter(a => ["message", "user"].includes(a.scope) && a.platforms.includes(message.platform) && !message.deleted)) {
      const option = document.createElement("option"); option.value = `configured:${action.id}`; option.textContent = `${action.scope}: ${action.label}`; actions.append(option)
    }
    actions.addEventListener("change", async () => {
      const action = actions.value; actions.value = ""
      if (action.startsWith("configured:")) {
        actions.disabled = true
        try { await request("/api/configured-action", {id:action.slice("configured:".length), platform:message.platform, identity:message.identity}); status.textContent = "Action queued." }
        catch (error) { status.textContent = String(error) } finally { actions.disabled = false }
        return
      }
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
  if (atBottom && !preferences.newestFirst) history.scrollTop = history.scrollHeight
}
element("view").addEventListener("change", render)
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
platform.addEventListener("change", () => { suggest(); render() })
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
      case "/pause": pausedIdentities = new Set(messages.map(m => m.identity)); pausedEventIds = new Set(events.map(e => e.eventId)); render(); status.textContent = "View paused. Use /resume to show incoming messages."; break
      case "/resume": pausedIdentities = undefined; pausedEventIds = undefined; render(); status.textContent = "View resumed."; break
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
    const snapshot = await request("/api/chat") as { messages: Message[]; emotes: Emote[]; actions?: ConfiguredAction[]; events?: FeedEvent[]; preferences?: Preferences & Record<string, unknown>; completions?: Record<string, Completion[]> }
    const next = JSON.stringify([snapshot.messages, snapshot.preferences, snapshot.events, snapshot.actions])
    events = snapshot.events ?? []; configuredActions = snapshot.actions ?? []
    if (snapshot.preferences) { preferences = snapshot.preferences; storedPreferences = snapshot.preferences }
    emotes = snapshot.emotes
    completions = snapshot.completions ?? {}
    if (next !== signature) { signature = next; messages = snapshot.messages; render() }
    if (status.textContent?.startsWith("Error:")) status.textContent = "Connected."
  } catch (error) { status.textContent = String(error) }
  setTimeout(poll, 1000)
}
element("preferences-toggle").addEventListener("click", () => {
  const panel = element("preferences"); panel.hidden = !panel.hidden
  element("preferences-toggle").setAttribute("aria-expanded", String(!panel.hidden))
  element<HTMLSelectElement>("chat-font").value = preferences.font
  element<HTMLInputElement>("font-size").value = String(preferences.fontSize)
  element<HTMLInputElement>("timestamps").checked = preferences.timestamps
  element<HTMLInputElement>("newest-first").checked = preferences.newestFirst
  element<HTMLInputElement>("alternating-rows").checked = preferences.alternatingRows
})
element("save-preferences").addEventListener("click", async () => {
  if (!storedPreferences) { status.textContent = "Chat preferences have not loaded yet."; return }
  const size = element<HTMLInputElement>("font-size").valueAsNumber
  if (!Number.isFinite(size) || size < 10 || size > 28) { status.textContent = "Font size must be between 10 and 28."; return }
  const button = element<HTMLButtonElement>("save-preferences"); button.disabled = true
  try {
    await request("/api/preferences", { ...storedPreferences, fontSize: size, font: element<HTMLSelectElement>("chat-font").value,
      timestamps: element<HTMLInputElement>("timestamps").checked, newestFirst: element<HTMLInputElement>("newest-first").checked,
      alternatingRows: element<HTMLInputElement>("alternating-rows").checked })
    status.textContent = "Preferences saved."
  } catch (error) { status.textContent = String(error) }
  finally { button.disabled = false }
})
void poll()
