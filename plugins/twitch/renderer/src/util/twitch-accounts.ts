import { TwitchAccountConfig } from "showrunner-plugin-twitch-shared"
import { AccountState, ResourceData } from "showrunner-schema"
import { useResource } from "showrunner-ui-core"

export function useChannelAccountResource() {
	return useResource<ResourceData<TwitchAccountConfig, AccountState>>("TwitchAccount", "channel")
}

export function useBotAccountResource() {
	return useResource<ResourceData<TwitchAccountConfig, AccountState>>("TwitchAccount", "bot")
}
