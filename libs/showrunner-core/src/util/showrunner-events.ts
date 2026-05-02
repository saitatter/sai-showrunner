import { EventList } from "./events"

export interface ShowRunnerChatModerationEvent {
	id: string
	platform: string
	source: string
	receivedAt: string
	actor: Record<string, unknown> & { badges?: string[] }
	payload: Record<string, unknown>
}

export const showrunnerChatModerationEvents = new EventList<
	(event: ShowRunnerChatModerationEvent) => Promise<void> | void
>()
