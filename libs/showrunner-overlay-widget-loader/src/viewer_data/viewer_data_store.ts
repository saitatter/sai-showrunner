import type { Unsubscribe, ViewerDataAccess, ViewerDataObserver, ViewerDataRow, ViewerVariable } from "showrunner-overlay-core"

/** Multiplexes viewer-data observation while keeping queries at the bridge boundary. */
export class ViewerDataStore implements ViewerDataAccess {
	private readonly observers = new Set<ViewerDataObserver>()

	constructor(
		private readonly onObserve: () => void = () => {},
		private readonly onUnobserve: () => void = () => {},
		private readonly onQuery: ViewerDataAccess["query"] = async () => [],
		private readonly onGetVariables: ViewerDataAccess["getVariables"] = async () => []
	) {}

	observe(observer: ViewerDataObserver): Unsubscribe {
		if (this.observers.has(observer)) return () => this.observers.delete(observer)
		const wasEmpty = this.observers.size === 0
		this.observers.add(observer)
		if (wasEmpty) this.onObserve()
		return () => {
			if (!this.observers.delete(observer)) return
			if (this.observers.size === 0) this.onUnobserve()
		}
	}

	query(start: number, end: number, sortBy?: string, sortOrder?: number): Promise<ViewerDataRow[]> {
		return this.onQuery(start, end, sortBy, sortOrder)
	}

	getVariables(): Promise<ViewerVariable[]> {
		return this.onGetVariables()
	}

	newRow(provider: string, id: string, row: ViewerDataRow): void {
		for (const observer of this.observers) observer.onNewViewerData?.(provider, id, { [provider]: id, ...row })
	}

	reconnect(): void {
		if (this.observers.size > 0) this.onObserve()
	}

	changed(provider: string, id: string, variable: string, value: unknown): void {
		for (const observer of this.observers) observer.onViewerDataChanged?.(provider, id, variable, value)
	}

	removed(provider: string, id: string): void {
		for (const observer of this.observers) observer.onViewerDataRemoved?.(provider, id)
	}

	newVariable(variable: ViewerVariable): void {
		for (const observer of this.observers) observer.onNewViewerVariable?.(variable)
	}

	deleteVariable(name: string): void {
		for (const observer of this.observers) observer.onViewerVariableDeleted?.(name)
	}
}
