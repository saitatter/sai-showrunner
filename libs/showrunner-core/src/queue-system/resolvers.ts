import { AutomationSource, InlineAutomation, Schema } from "showrunner-schema"
import { Service } from "../util/service"

/**
 * Debugger interface for tracking execution progress.
 * Used by both GraphVM and the test runner UI.
 */
export interface ExecutionDebugger {
	executionStarted(): void
	executionEnded(): void
	markStart(id: string): void
	markEnd(id: string): void
	logResult(id: string, result: any): void
	logError(id: string, err: any): void
}

interface ActionResolverImpl {
	getAutomation(id: string, subId?: string): InlineAutomation | undefined
	getContextSchema(id: string, subId?: string): Promise<Schema | undefined>
	getRunWrapper(id: string, subId?: string): (inner: () => any, mapping: AutomationSource) => Promise<any>
}

export const ActionResolvers = Service(
	class {
		private lookup = new Map<string, ActionResolverImpl>()

		getResolver(type: string) {
			return this.lookup.get(type)
		}

		registerResolver(type: string, resolver: ActionResolverImpl) {
			this.lookup.set(type, resolver)
		}
	}
)
