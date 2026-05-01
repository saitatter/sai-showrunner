import { BrowserWindow } from "electron"
import { createServer } from "node:http"
import { AddressInfo } from "node:net"
import { createHash, randomBytes } from "node:crypto"
import {
	ensureDirectory,
	ensureYAML,
	loadSecretYAML,
	loadYAML,
	resolveProjectPath,
	writeSecretYAML,
	writeYAML,
} from "castmate-core"
import { YouTubeSecrets, YouTubeSettings } from "castmate-plugin-youtube-shared"

const DEFAULT_SCOPES = [
	"https://www.googleapis.com/auth/youtube.readonly",
	"https://www.googleapis.com/auth/youtube.force-ssl",
]

const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
const TOKEN_URL = "https://oauth2.googleapis.com/token"
const BUNDLED_CLIENT_ID = process.env.SHOWRUNNER_YOUTUBE_CLIENT_ID?.trim() || ""
const BUNDLED_CLIENT_SECRET = process.env.SHOWRUNNER_YOUTUBE_CLIENT_SECRET?.trim() || ""

export interface YouTubeSettingsUpdate extends Partial<YouTubeSettings> {
	clientSecret?: string
}

export interface YouTubeProfile {
	channelId: string
	title: string
}

function base64Url(buffer: Buffer) {
	return buffer
		.toString("base64")
		.replace(/\+/g, "-")
		.replace(/\//g, "_")
		.replace(/=+$/g, "")
}

function createPkcePair() {
	const verifier = base64Url(randomBytes(64))
	const challenge = base64Url(createHash("sha256").update(verifier).digest())
	return { verifier, challenge }
}

async function readJsonResponse<T>(response: Response): Promise<T> {
	const body = await response.text()
	if (!response.ok) {
		throw new Error(body || `Request failed with ${response.status}`)
	}
	return JSON.parse(body) as T
}

export class YouTubeAuthService {
	private settings: YouTubeSettings = {
		clientId: "",
		scopes: DEFAULT_SCOPES,
		autoStartLiveChat: false,
	}
	private secrets: YouTubeSecrets = {}
	private refreshPromise: Promise<void> | undefined

	async initialize() {
		await ensureDirectory(resolveProjectPath("youtube"))
		await ensureYAML(this.settings, "youtube", "settings.yaml")
		this.settings = await loadYAML<YouTubeSettings>("youtube", "settings.yaml")
		try {
			this.secrets = await loadSecretYAML<YouTubeSecrets>("youtube", "secrets.syaml")
		} catch {
			this.secrets = {}
		}
	}

	getSettings() {
		return {
			...this.settings,
			hasBundledClientId: Boolean(BUNDLED_CLIENT_ID),
			hasBundledClientSecret: Boolean(BUNDLED_CLIENT_SECRET),
			clientSecretConfigured: Boolean(this.effectiveClientSecret),
			clientIdSource: this.clientIdSource,
		}
	}

	private get effectiveClientId() {
		return this.settings.clientId?.trim() || BUNDLED_CLIENT_ID
	}

	private get clientIdSource() {
		if (this.settings.clientId?.trim()) return "manual"
		if (BUNDLED_CLIENT_ID) return "bundled"
		return "missing"
	}

	private get effectiveClientSecret() {
		return this.secrets.clientSecret?.trim() || BUNDLED_CLIENT_SECRET
	}

	get hasUsableToken() {
		return Boolean(this.secrets.accessToken && (!this.secrets.expiresAt || this.secrets.expiresAt > Date.now() + 60000))
	}

	get hasStoredRefreshToken() {
		return Boolean(this.secrets.refreshToken)
	}

	async saveSettings(settings: YouTubeSettingsUpdate) {
		const { clientSecret, ...publicSettings } = settings
		this.settings = {
			...this.settings,
			...publicSettings,
			scopes: publicSettings.scopes?.length ? publicSettings.scopes : this.settings.scopes,
			autoStartLiveChat: publicSettings.autoStartLiveChat ?? this.settings.autoStartLiveChat,
		}
		if (typeof clientSecret === "string") {
			const nextSecret = clientSecret.trim()
			this.secrets = {
				...this.secrets,
				clientSecret: nextSecret || undefined,
			}
			await writeSecretYAML(this.secrets, "youtube", "secrets.syaml")
		}
		await writeYAML(this.settings, "youtube", "settings.yaml")
		return this.getSettings()
	}

	async clear() {
		this.secrets = {}
		await writeSecretYAML(this.secrets, "youtube", "secrets.syaml")
	}

	async getAccessToken() {
		if (this.hasUsableToken) return this.secrets.accessToken
		if (!this.secrets.refreshToken) return undefined
		await this.refreshOnce()
		return this.secrets.accessToken
	}

	async authorizedFetch<T>(url: string | URL) {
		const accessToken = await this.getAccessToken()
		if (!accessToken) throw new Error("YouTube access token is missing.")
		let response = await fetch(url, {
			headers: {
				authorization: `Bearer ${accessToken}`,
			},
		})

		if (response.status === 401 && this.secrets.refreshToken) {
			await this.refreshOnce()
			response = await fetch(url, {
				headers: {
					authorization: `Bearer ${this.secrets.accessToken}`,
				},
			})
		}

		return readJsonResponse<T>(response)
	}

	async login() {
		const clientId = this.effectiveClientId
		const clientSecret = this.effectiveClientSecret
		if (!clientId) {
			throw new Error("Configure a Google OAuth desktop client ID before connecting YouTube or build ShowRunner with SHOWRUNNER_YOUTUBE_CLIENT_ID.")
		}

		const { verifier, challenge } = createPkcePair()
		const state = base64Url(randomBytes(24))
		const redirect = await this.createLoopbackRedirect(state)
		const authUrl = new URL(AUTH_URL)
		authUrl.searchParams.set("client_id", clientId)
		authUrl.searchParams.set("redirect_uri", redirect.redirectUri)
		authUrl.searchParams.set("response_type", "code")
		authUrl.searchParams.set("scope", this.settings.scopes.join(" "))
		authUrl.searchParams.set("access_type", "offline")
		authUrl.searchParams.set("prompt", "consent")
		authUrl.searchParams.set("code_challenge", challenge)
		authUrl.searchParams.set("code_challenge_method", "S256")
		authUrl.searchParams.set("state", state)

		const window = new BrowserWindow({
			width: 860,
			height: 720,
			title: "Connect YouTube",
			webPreferences: {
				nodeIntegration: false,
				contextIsolation: true,
				partition: "persist:youtube-auth",
			},
		})

		try {
			await window.loadURL(authUrl.toString())
			const code = await Promise.race([
				redirect.waitForCode(),
				new Promise<string>((_, reject) => {
					window.on("closed", () => reject(new Error("YouTube login window was closed.")))
				}),
			])
			await this.exchangeCode(code, verifier, redirect.redirectUri, clientId, clientSecret)
			return await this.fetchProfile()
		} finally {
			redirect.close()
			if (!window.isDestroyed()) window.close()
		}
	}

	private createLoopbackRedirect(expectedState: string) {
		let resolveCode: (code: string) => void
		let rejectCode: (error: Error) => void

		const promise = new Promise<string>((resolve, reject) => {
			resolveCode = resolve
			rejectCode = reject
		})

		const server = createServer((request, response) => {
			const url = new URL(request.url || "/", "http://127.0.0.1")
			if (url.pathname !== "/oauth/youtube/callback") {
				response.writeHead(404)
				response.end()
				return
			}

			const error = url.searchParams.get("error")
			const code = url.searchParams.get("code")
			const receivedState = url.searchParams.get("state")

			response.writeHead(error || !code ? 400 : 200, { "content-type": "text/html; charset=utf-8" })
			response.end(error ? "YouTube login failed. You can close this window." : "YouTube connected. You can close this window.")

			if (error) {
				rejectCode(new Error(error))
				return
			}

			if (!code) {
				rejectCode(new Error("Google OAuth did not return an authorization code."))
				return
			}

			if (receivedState !== expectedState) {
				rejectCode(new Error("Google OAuth state did not match."))
				return
			}

			resolveCode(code)
		})

		return new Promise<{
			redirectUri: string
			waitForCode: () => Promise<string>
			close: () => void
		}>((resolve, reject) => {
			server.once("error", reject)
			server.listen(0, "127.0.0.1", () => {
				const address = server.address() as AddressInfo
				resolve({
					redirectUri: `http://127.0.0.1:${address.port}/oauth/youtube/callback`,
					waitForCode: () => promise,
					close: () => server.close(),
				})
			})
		})
	}

	private async exchangeCode(code: string, verifier: string, redirectUri: string, clientId: string, clientSecret?: string) {
		const body = new URLSearchParams({
			client_id: clientId,
			code,
			code_verifier: verifier,
			grant_type: "authorization_code",
			redirect_uri: redirectUri,
		})
		if (clientSecret) body.set("client_secret", clientSecret)

		const response = await fetch(TOKEN_URL, {
			method: "POST",
			headers: { "content-type": "application/x-www-form-urlencoded" },
			body,
		})
		const token = await readJsonResponse<{
			access_token: string
			refresh_token?: string
			expires_in?: number
			scope?: string
			token_type?: string
		}>(response)

		this.secrets = {
			...this.secrets,
			accessToken: token.access_token,
			refreshToken: token.refresh_token || this.secrets.refreshToken,
			expiresAt: token.expires_in ? Date.now() + token.expires_in * 1000 : undefined,
			scope: token.scope,
			tokenType: token.token_type,
		}
		await writeSecretYAML(this.secrets, "youtube", "secrets.syaml")
	}

	private async refresh() {
		const clientId = this.effectiveClientId
		const clientSecret = this.effectiveClientSecret
		if (!clientId || !this.secrets.refreshToken) {
			throw new Error("YouTube refresh token is missing.")
		}
		const body = new URLSearchParams({
			client_id: clientId,
			refresh_token: this.secrets.refreshToken,
			grant_type: "refresh_token",
		})
		if (clientSecret) body.set("client_secret", clientSecret)

		const response = await fetch(TOKEN_URL, {
			method: "POST",
			headers: { "content-type": "application/x-www-form-urlencoded" },
			body,
		})
		const token = await readJsonResponse<{
			access_token: string
			expires_in?: number
			scope?: string
			token_type?: string
		}>(response)

		this.secrets = {
			...this.secrets,
			accessToken: token.access_token,
			expiresAt: token.expires_in ? Date.now() + token.expires_in * 1000 : undefined,
			scope: token.scope,
			tokenType: token.token_type,
		}
		await writeSecretYAML(this.secrets, "youtube", "secrets.syaml")
	}

	private async refreshOnce() {
		this.refreshPromise ??= this.refresh().finally(() => {
			this.refreshPromise = undefined
		})
		return this.refreshPromise
	}

	async fetchProfile(): Promise<YouTubeProfile> {
		const data = await this.authorizedFetch<{
			items?: Array<{ id: string; snippet?: { title?: string } }>
		}>("https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true")
		const channel = data.items?.[0]
		if (!channel) throw new Error("No YouTube channel was returned for this account.")
		return {
			channelId: channel.id,
			title: channel.snippet?.title || channel.id,
		}
	}
}
