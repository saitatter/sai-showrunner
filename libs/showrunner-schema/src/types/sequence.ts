export interface AutomationSource {
	type: string
	id: string
	subId?: string
}

export interface AutomationProvider {
	getAutomation(id: string): unknown | undefined
}

export interface QueuedAutomation {
	id: string
	source: AutomationSource
	queueContext: ExecutionContext
}

export interface ExecutionContext {
	contextState: Record<string, any>
}

/** @deprecated Use AutomationSource. */
export type SequenceSource = AutomationSource

/** @deprecated Use AutomationProvider. */
export type SequenceProvider = AutomationProvider

/** @deprecated Use QueuedAutomation. */
export type QueuedSequence = QueuedAutomation

/** @deprecated Use ExecutionContext. */
export type SequenceContext = ExecutionContext

export interface ActionInfo {
	id: string
	plugin: string
	action: string
	config: any
	resultMapping?: Record<string, string>
}
