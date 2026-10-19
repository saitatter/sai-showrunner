import "./chat-dock.css"

type Message = { identity: string; platform: string; viewerName: string; message: string; isOwner: boolean; deleted: boolean }
type Emote = { name: string; text: string }
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

async function request(path: string, body?: unknown) {
  const response = await fetch(path, { method: body ? "POST" : "GET", headers: { "x-showrunner-chat": token, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined })
  if (!response.ok) throw new Error(response.status === 401 ? "Re-copy the OBS dock URL from ShowRunner Chat." : "Chat operation failed. Check the connection and permissions in ShowRunner.")
  return response.json()
}
function render() {
  const atBottom = history.scrollHeight - history.scrollTop - history.clientHeight < 50
  history.replaceChildren()
  for (const message of messages.filter(m => !filter.value || m.platform === filter.value)) {
    const row = document.createElement("article")
    const title = document.createElement("strong")
    title.textContent = `${message.platform} · ${message.viewerName}`
    const text = document.createElement("p")
    text.textContent = message.deleted ? "Message deleted" : message.message
    const actions = document.createElement("select")
    actions.setAttribute("aria-label", "Message actions")
    for (const [value, label] of [["", "Actions"], ["reply", "Reply"], ["copy", "Copy message"], ...(!message.deleted ? [["deleteMessage", "Delete message"]] : []), ...(!message.isOwner ? [["timeout", "Timeout 60s"], ["ban", "Ban user"], ...(message.platform === "twitch" ? [["unban", "Unban user"]] : [])] : [])]) {
      const option = document.createElement("option"); option.value = value; option.textContent = label; actions.append(option)
    }
    actions.addEventListener("change", async () => {
      const action = actions.value; actions.value = ""
      if (action === "reply") { platform.value = message.platform; input.value = `@${message.viewerName} `; input.focus(); return }
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
filter.addEventListener("change", render)
input.addEventListener("input", () => {
  const suggestions = element<HTMLElement>("emotes"); suggestions.replaceChildren()
  const cursor = input.selectionStart ?? input.value.length
  const word = input.value.slice(0, cursor).split(/\s/).at(-1) ?? ""
  if (word.length < 2) return
  for (const emote of emotes.filter(e => (platform.value === "twitch" || e.name.startsWith(":")) && e.name.toLowerCase().startsWith(word.toLowerCase())).slice(0, 8)) {
    const button = document.createElement("button"); button.type = "button"; button.textContent = emote.name
    button.addEventListener("click", () => { input.setRangeText(`${emote.text} `, cursor - word.length, cursor, "end"); suggestions.replaceChildren(); input.focus() })
    suggestions.append(button)
  }
})
form.addEventListener("submit", async event => {
  event.preventDefault()
  const button = form.querySelector("button")!; button.disabled = true
  const sentText = input.value
  try { await request("/api/send", { platform: platform.value, message: sentText }); if (input.value === sentText) input.value = ""; status.textContent = "Message sent." }
  catch (error) { status.textContent = String(error) }
  finally { button.disabled = false }
})
async function poll() {
  try {
    const snapshot = await request("/api/chat") as { messages: Message[]; emotes: Emote[] }
    const next = JSON.stringify(snapshot.messages)
    emotes = snapshot.emotes
    if (next !== signature) { signature = next; messages = snapshot.messages; render() }
    if (status.textContent?.startsWith("Error:")) status.textContent = "Connected."
  } catch (error) { status.textContent = String(error) }
  setTimeout(poll, 1000)
}
void poll()
