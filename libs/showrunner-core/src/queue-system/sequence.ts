import { PluginManager } from "../plugins/plugin-manager"
import { reactify } from "../reactivity/reactivity"
import { setAbortableTimeout } from "../util/abort-utils"
import { deserializeSchema } from "../util/ipc-schema"
import { SemanticVersion } from "../util/type-helpers"

import {
	Sequence,
	ActionInfo,
	ActionStack,
	TimeAction,
	InstantAction,
	SequenceActions,
	OffsetActions,
	FlowAction,
	isActionStack,
	isTimeAction,
	isFlowAction,
	SequenceContext,
	mapRecord,
	Schema,
	InlineAutomation,
	hashString,
	SequenceSource,
	AutomationDataWire,
	AutomationVariableNode,
} from "ShowRunner-schema"
import { ActionInvokeContextData } from "./action"
import { globalLogger } from "../logging/logging"
import { Service } from "../util/service"
import { templateSchema } from "../templates/template"

export interface SequenceDebugger {
	sequenceStarted(): void
	sequenceEnded(): void
	markStart(id: string): void
	markEnd(id: string): void
	logResult(id: string, result: any): void
	logError(id: string, err: any): void
}

type SequenceCompletion = "complete" | "aborted"

export class SequenceRunner {
	private abortController = new AbortController()
	private disconnectedFlows = new Array<Promise<any>>()
	private nodeResults = new Map<string, Record<string, any>>()

	constructor(
		private sequence: Sequence,
		private context: SequenceContext,
		private dbg?: SequenceDebugger,
		private dataWires?: AutomationDataWire[],
		private variableNodes?: AutomationVariableNode[]
	) {
		// Populate variable node values into results map so wires from variables resolve
		if (variableNodes) {
			for (const v of variableNodes) {
				this.nodeResults.set(v.id, { value: v.value })
			}
		}

		// Validate wires: filter out any that reference non-existent nodes
		if (dataWires?.length) {
			const actionIds = new Set<string>()
			const collectIds = (seq: SequenceActions) => {
				for (const action of seq.actions) {
					if (isActionStack(action)) {
						for (const a of action.stack) actionIds.add(a.id)
					} else if (isFlowAction(action)) {
						actionIds.add(action.id)
						for (const f of action.subFlows) collectIds(f)
					} else {
						actionIds.add(action.id)
					}
				}
			}
			collectIds(sequence)
			for (const v of variableNodes ?? []) actionIds.add(v.id)

			const validWires = dataWires.filter((w) => {
				if (!actionIds.has(w.fromNode) || !actionIds.has(w.toNode)) {
					globalLogger.log(`Data wire ${w.id} references missing node, skipping`)
					return false
				}
				return true
			})
			this.dataWires = validWires
		}
	}

	abort() {
		this.abortController.abort()
	}

	get aborted() {
		return this.abortController.signal.aborted
	}

	async run(): Promise<SequenceCompletion> {
		this.dbg?.sequenceStarted()
		const completion = await this.runSequence(this.sequence)
		await Promise.allSettled(this.disconnectedFlows)
		this.dbg?.sequenceEnded()
		return completion
	}

	private async runActionBase(action: ActionInfo) {
		this.dbg?.markStart(action.id)
		try {
			const actionDef = PluginManager.getInstance().getAction(action.plugin, action.action)
			if (!actionDef || actionDef.type != "regular") {
				throw new Error(`Unknown Action: ${action.plugin}:${action.action}`)
			}

			// Resolve data wire inputs: override config values with wired source outputs
			const resolvedConfig = this.resolveWireInputs(action.id, action.config)
			const deserializedConfig = await deserializeSchema(actionDef.configSchema, resolvedConfig)
			//Todo construct action context
			const actionContext: ActionInvokeContextData = this.context
			const result = await actionDef.invoke(deserializedConfig, actionContext, this.abortController.signal)
			this.dbg?.logResult(action.id, result)

			// Store result for data wire lookups by downstream nodes
			if (result != null) {
				if (typeof result === "object") {
					this.nodeResults.set(action.id, result)
				} else {
					// Wrap primitives so port "_result" can reference them
					this.nodeResults.set(action.id, { _result: result })
				}
			}

			// Propagate wired values to variable nodes (write-through)
			this.propagateToVariableNodes(action.id)

			let resultMapped: Record<string, any> = {}

			if (action.resultMapping) {
				for (const key in action.resultMapping) {
					resultMapped[action.resultMapping[key]] = result[key]
				}
			}

			this.context.contextState = {
				...this.context.contextState,
				...resultMapped,
			}

			return result
		} catch (err) {
			globalLogger.error("Error ", action.plugin, action.action, err)
			this.dbg?.logError(action.id, err)
			return undefined
		} finally {
			this.dbg?.markEnd(action.id)
		}
	}

	/** Resolve incoming data wires for a node, overwriting config fields with wired values */
	private resolveWireInputs(nodeId: string, config: any): any {
		if (!this.dataWires?.length || !config || typeof config !== "object") return config
		const incomingWires = this.dataWires.filter((w) => w.toNode === nodeId)
		if (incomingWires.length === 0) return config

		const resolved = { ...config }
		for (const wire of incomingWires) {
			const sourceResult = this.nodeResults.get(wire.fromNode)
			if (sourceResult === undefined) {
				globalLogger.log(`Data wire: source node "${wire.fromNode}" has no result (wire ${wire.id})`)
				continue
			}
			if (!(wire.fromPort in sourceResult)) {
				globalLogger.log(`Data wire: port "${wire.fromPort}" not found in node "${wire.fromNode}" result (wire ${wire.id})`)
				continue
			}
			resolved[wire.toPort] = sourceResult[wire.fromPort]
		}
		return resolved
	}

	/** After an action runs, propagate its output to any variable nodes connected via wires */
	private propagateToVariableNodes(sourceNodeId: string) {
		if (!this.dataWires?.length || !this.variableNodes?.length) return
		const variableIds = new Set(this.variableNodes.map((v) => v.id))
		const outgoing = this.dataWires.filter((w) => w.fromNode === sourceNodeId && variableIds.has(w.toNode))
		for (const wire of outgoing) {
			const sourceResult = this.nodeResults.get(wire.fromNode)
			if (!sourceResult || !(wire.fromPort in sourceResult)) continue
			const value = sourceResult[wire.fromPort]
			// Update both the variable node data and the nodeResults map
			const vn = this.variableNodes.find((v) => v.id === wire.toNode)
			if (vn) vn.value = value
			const existing = this.nodeResults.get(wire.toNode) ?? {}
			existing[wire.toPort] = value
			this.nodeResults.set(wire.toNode, existing)
		}
	}

	private async runFlowAction(action: FlowAction) {
		if (this.aborted) return
		this.dbg?.markStart(action.id)
		try {
			const actionDef = PluginManager.getInstance().getAction(action.plugin, action.action)
			if (!actionDef || actionDef.type != "flow") {
				throw new Error(`Unknown Action: ${action.plugin}:${action.action}`)
			}

			const deserializedConfig = await deserializeSchema(actionDef.configSchema, action.config)

			const flows: Record<string, any> = {}

			for (const flow of action.subFlows) {
				flows[flow.id] = actionDef.flowSchema
					? await deserializeSchema(actionDef.flowSchema, flow.config)
					: null
			}

			const subFlowId = await actionDef.invoke(
				deserializedConfig,
				flows,
				this.context,
				this.abortController.signal
			)

			const subFlow = action.subFlows.find((f) => f.id == subFlowId)

			if (subFlow) {
				await this.runSequence(subFlow)
			}
		} catch (err) {
			this.dbg?.logError(action.id, err)
		} finally {
			this.dbg?.markEnd(action.id)
		}
	}

	private async runAction(action: ActionStack | TimeAction | InstantAction) {
		if (this.aborted) return
		if (isActionStack(action)) {
			return await this.runActionStack(action)
		} else if (isTimeAction(action)) {
			return await this.runTimeAction(action)
		} else if (isFlowAction(action)) {
			return await this.runFlowAction(action)
		} else {
			return await this.runActionBase(action)
		}
	}

	/**
	 * Action Stacks have all actions executed simultaneously
	 * @param actionStack
	 */
	private async runActionStack(actionStack: ActionStack) {
		const promises = actionStack.stack.map((action) => this.runActionBase(action))
		return await Promise.all(promises)
	}
	/**
	 * Sequences run actions one after another, each waiting on the prior
	 * @param sequence
	 */
	private async runSequence(sequence: SequenceActions): Promise<SequenceCompletion> {
		for (let action of sequence.actions) {
			if (this.aborted) return "aborted"
			await this.runAction(action)
		}
		return this.aborted ? "aborted" : "complete"
	}

	/**
	 * A time action can have sequences attached at different delay points
	 * @param timeAction
	 */
	private async runTimeAction(timeAction: TimeAction) {
		const actionPromise = this.runActionBase(timeAction)

		//TODO: minDuration for unknown duration

		const promises = timeAction.offsets.map(async (offset) => {
			await this.runOffset(offset)
		})

		this.disconnectedFlows.push(...promises)

		await actionPromise

		//await Promise.allSettled([actionPromise, ...promises])
	}

	private runOffset(offset: OffsetActions) {
		return new Promise((resolve, reject) => {
			setAbortableTimeout(
				async () => {
					try {
						await this.runSequence(offset)
						resolve(undefined)
					} catch (err) {
						reject(err)
					}
				},
				offset.offset * 1000,
				this.abortController.signal,
				() => {
					resolve(undefined)
				}
			)
		})
	}
}

export function getSequenceHash(sequence: Sequence) {
	//Hack?
	return hashString(JSON.stringify(sequence))
}

interface SequenceResolverImpl {
	getAutomation(id: string, subId?: string): InlineAutomation | undefined
	getContextSchema(id: string, subId?: string): Promise<Schema | undefined>
	getRunWrapper(id: string, subId?: string): (inner: () => any, mapping: SequenceSource) => Promise<any>
}

export const SequenceResolvers = Service(
	class {
		private lookup = new Map<string, SequenceResolverImpl>()

		getResolver(type: string) {
			return this.lookup.get(type)
		}

		registerResolver(type: string, resolver: SequenceResolverImpl) {
			this.lookup.set(type, resolver)
		}
	}
)
