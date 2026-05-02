import { Duration } from "../data/duration"
import { QueuedAutomation } from "./sequence"

export interface ActionQueueConfig {
	name: string
	paused: boolean
	gap: Duration
}

export interface ActionQueueState {
	running?: QueuedAutomation
	queue: QueuedAutomation[]
	history: QueuedAutomation[]
}
