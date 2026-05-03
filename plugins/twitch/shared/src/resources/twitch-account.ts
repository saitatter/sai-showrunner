import { AccountConfig } from "showrunner-schema"

export interface TwitchAccountSecrets {
	accessToken: string
}

export interface TwitchAccountConfig extends AccountConfig {
	twitchId: string
	isAffiliate: boolean
	isPartner: boolean
	email?: string
}
