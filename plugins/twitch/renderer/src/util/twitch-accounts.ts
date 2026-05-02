import { TwitchAccountConfig } from "ShowRunner-plugin-twitch-shared"
import { AccountState, ResourceData } from "ShowRunner-schema"
import { useResource } from "ShowRunner-ui-core"

export function useChannelAccountResource() {
	return useResource<ResourceData<TwitchAccountConfig, AccountState>>("TwitchAccount", "channel")
}

export function useBotAccountResource() {
	return useResource<ResourceData<TwitchAccountConfig, AccountState>>("TwitchAccount", "bot")
}
