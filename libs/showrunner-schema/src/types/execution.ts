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

export interface ActionInfo {
	id: string
	plugin: string
	action: string
	config: any
	resultMapping?: Record<string, string>
}
