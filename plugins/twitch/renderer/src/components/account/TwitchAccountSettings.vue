<template>
	<div class="twitch-accounts">
		<section class="twitch-accounts__status">
			<div :class="['twitch-accounts__card', channelAccount?.state.authenticated ? 'ok' : 'warn']">
				<i class="mdi mdi-twitch" />
				<div>
					<strong>Channel Account</strong>
					<span>{{ accountLabel(channelAccount, "Not connected") }}</span>
				</div>
			</div>
			<div :class="['twitch-accounts__card', botAccount?.state.authenticated ? 'ok' : 'warn']">
				<i class="mdi mdi-robot" />
				<div>
					<strong>Bot Account</strong>
					<span>{{ accountLabel(botAccount, "Not connected") }}</span>
				</div>
			</div>
		</section>

		<div class="twitch-accounts__login">
			<div class="flex flex-column align-items-center gap-1">
				<h3 class="my-0">Channel Account</h3>
				<span class="my-0 text-300">Sign into your main channel account here.</span>
				<account-widget account-type="TwitchAccount" account-id="channel" />
			</div>
			<div class="flex flex-column align-items-center gap-1">
				<h3 class="my-0">Bot Account</h3>
				<span class="my-0 text-300">This account is used to send chat messages.</span>
				<account-widget account-type="TwitchAccount" account-id="bot" />
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { TwitchAccountConfig } from "showrunner-plugin-twitch-shared"
import { AccountState, ResourceData } from "showrunner-schema"
import { AccountWidget } from "showrunner-ui-core"
import { useBotAccountResource, useChannelAccountResource } from "../../util/twitch-accounts"

const channelAccount = useChannelAccountResource()
const botAccount = useBotAccountResource()

function accountLabel(account: ResourceData<TwitchAccountConfig, AccountState> | undefined, fallback: string) {
	if (!account?.state.authenticated) return fallback
	return account.config.name || account.config.twitchId || "Connected"
}
</script>

<style scoped>
.twitch-accounts {
	display: grid;
	gap: 1rem;
	padding: 1rem;
}

.twitch-accounts__status {
	display: grid;
	gap: 0.75rem;
	grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
}

.twitch-accounts__card {
	align-items: center;
	background: var(--surface-900);
	border: 1px solid var(--surface-700);
	border-radius: 6px;
	display: grid;
	gap: 0.75rem;
	grid-template-columns: 2.25rem 1fr;
	padding: 0.85rem;
}

.twitch-accounts__card i {
	align-items: center;
	background: var(--surface-800);
	border-radius: 4px;
	display: flex;
	font-size: 1.4rem;
	height: 2.25rem;
	justify-content: center;
}

.twitch-accounts__card.ok i {
	color: #2ed47a;
}

.twitch-accounts__card.warn i {
	color: #ffc857;
}

.twitch-accounts__card strong,
.twitch-accounts__card span {
	display: block;
}

.twitch-accounts__card span {
	color: var(--text-color-secondary);
}

.twitch-accounts__login {
	display: flex;
	gap: 1rem;
	justify-content: center;
	margin-top: 0.5rem;
}
</style>
