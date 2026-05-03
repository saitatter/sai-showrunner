import { AccountConfig, AccountSecrets } from "showrunner-schema"

export interface WyzeAccountSecrets extends AccountSecrets {
	accessToken?: string
	refreshToken?: string
}

export interface WyzeAccountConfig extends AccountConfig {
	email: string
}
