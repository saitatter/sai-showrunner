import { ResourceStorage, Resource } from "../resources/resource"
import type { ResourceConstructor } from "../resources/resource"
import {
	AutomationSource,
	QueuedAutomation,
	ActionQueueConfig,
	ActionQueueState,
	Schema,
	constructDefault,
	AutomationData,
	InlineAutomation,
	addDefaults,
	isTriggerData,
} from "ShowRunner-schema"
import { nanoid } from "nanoid/non-secure"
import { Service } from "../util/service"
import { ExecutionDebugger, ActionResolvers } from "./resolvers"
import { defineCallableIPC, defineIPCFunc } from "../util/electron"
import { Profile } from "../profile/profile"
import { FileResource } from "../resources/file-resource"
import { ResourceRegistry } from "../resources/resource-registry"
import { deserializeSchema, exposeSchema, serializeSchema } from "../util/ipc-schema"
import { PluginManager } from "../plugins/plugin-manager"
import { usePluginLogger } from "../logging/logging"
import { GraphCompiler } from "../graph-engine/compiler"
import { GraphVM } from "../graph-engine/vm"

const logger = usePluginLogger("queues")

export class ActionQueue extends FileResource<ActionQueueConfig, ActionQueueState> {
	static resourceDirectory: string = "./queues"
	static storage = new ResourceStorage<ActionQueue>("ActionQueue")

	private activeVM: GraphVM | null = null
	private lastCompletion: number | null = null
	private scheduledId: string | undefined = undefined
	private scheduler: NodeJS.Timeout | undefined = undefined

	constructor(config?: ActionQueueConfig) {
		super()

		if (config) {
			this._id = nanoid()
			this._config = config
		} else {
			this._config = { name: "", paused: false, gap: 0 }
		}

		this.state = {
			history: [],
			running: undefined,
			queue: [],
		}
	}

	get isRunning() {
		return this.activeVM != null
	}

	get isReady() {
		return !this.isRunning || this.scheduler == null
	}

	/**
	 * If a queue is paused it will finish running the current sequence, but not start a new one.
	 */
	get isPaused() {
		return this.config.paused
	}

	async setConfig(config: ActionQueueConfig): Promise<boolean> {
		const result = await super.setConfig(config)
		this.checkQueueStart()
		return result
	}

	async applyConfig(config: Partial<ActionQueueConfig>): Promise<boolean> {
		const result = await super.applyConfig(config)
		this.checkQueueStart()
		return result
	}

	get gap() {
		return this.config.gap ?? 0
	}

	//Restarts the queue processing if it needs to
	private checkQueueStart() {
		if (this.config.paused) return

		if (this.isReady) {
			this.runNext()
		}
	}

	enqueue(source: AutomationSource, context: Record<string, any>) {
		this.state.queue.push({
			id: nanoid(),
			queueContext: { contextState: context },
			source,
		})

		this.checkQueueStart()
	}

	private pushToHistory(qs: QueuedAutomation) {
		this.state.history.unshift(qs)
		if (this.state.history.length > 20) {
			//Todo: Configurable?
			this.state.history.pop()
		}
	}

	private clearScheduled() {
		if (!this.scheduler) return

		this.scheduledId = undefined
		clearTimeout(this.scheduler)
		this.scheduler = undefined
	}

	skip(id: string) {
		if (this.state.running?.id == id) {
			this.activeVM?.abort()
		} else {
			const idx = this.state.queue.findIndex((i) => i.id == id)
			if (idx < 0) return

			if (id == this.scheduledId) {
				//Make sure to stop a scheduled
				this.clearScheduled()

				if (!this.isPaused) {
					this.runNext() //Start the next one
				}
			}
			this.state.queue.splice(idx, 1)
		}
	}

	spliceQueue(index: number, deleteCount: number, ...sequence: QueuedAutomation[]) {
		this.state.queue.splice(index, deleteCount, ...sequence)
	}

	replay(id: string) {
		const played = this.state.history.find((i) => i.id == id)
		if (!played) return

		this.enqueue(played.source, played.queueContext.contextState)
	}

	private getNextSequence(): QueuedAutomation | undefined {
		return this.state.queue.shift()
	}

	private async runNext() {
		if (this.activeVM || this.state.running) {
			return
		}

		const seqItem = this.getNextSequence()

		if (!seqItem) return

		const resolver = ActionResolvers.getInstance().getResolver(seqItem.source.type)

		if (!resolver) return

		const automation = resolver.getAutomation(seqItem.source.id, seqItem.source.subId)
		const contextSchema = await resolver.getContextSchema(seqItem.source.id, seqItem.source.subId)
		const wrapper = resolver.getRunWrapper(seqItem.source.id, seqItem.source.subId)

		if (!automation) return
		if (!contextSchema) return

		const deserializedContext = await deserializeSchema(contextSchema, seqItem.queueContext.contextState)
		const finalContext = await exposeSchema(contextSchema, deserializedContext)

		if (!automation.graph) {
			logger.error("Automation missing graph — cannot execute", seqItem.source)
			this.pushToHistory(seqItem)
			return
		}

		const compiler = new GraphCompiler()
		const program = compiler.compile(automation.graph, automation.subgraphs, automation.dataWires)
		this.activeVM = new GraphVM(program, { contextState: finalContext })
		this.state.running = seqItem

		const doRun = async () => {
			try {
				await wrapper(async () => await this.activeVM?.execute(), seqItem.source)
			} finally {
				this.lastCompletion = Date.now()
				this.activeVM = null
				this.state.running = undefined
				this.pushToHistory(seqItem)
				if (!this.isPaused) {
					this.runNext()
				}
			}
		}

		let remaining = 0
		if (this.lastCompletion != null) {
			const now = Date.now()
			const diff = (now - this.lastCompletion) / 1000
			remaining = Math.max(0, this.gap - diff)
		}

		this.scheduler = setTimeout(() => {
			this.scheduler = undefined
			doRun()
		}, remaining * 1000)
	}

	static async initialize() {
		await super.initialize()

		const resourceConstructor = ActionQueue as unknown as ResourceConstructor<ActionQueue>
		ResourceRegistry.getInstance().exposeIPCFunction(resourceConstructor, "skip")
		ResourceRegistry.getInstance().exposeIPCFunction(resourceConstructor, "replay")
		ResourceRegistry.getInstance().exposeIPCFunction(resourceConstructor, "spliceQueue")
	}
}

const markTestActionStart = defineCallableIPC<(sequenceId: string, id: string) => void>(
	"actionQueue",
	"markTestActionStart"
)
const markTestActionEnd = defineCallableIPC<(sequenceId: string, id: string) => void>(
	"actionQueue",
	"markTestActionEnd"
)
const markTestSequenceStart = defineCallableIPC<(sequenceId: string) => void>("actionQueue", "markTestSequenceStart")
const markTestSequenceEnd = defineCallableIPC<(sequenceId: string) => void>("actionQueue", "markTestSequenceEnd")
const markTestActionResult = defineCallableIPC<(sequenceId: string, id: string, result: any) => void>(
	"actionQueue",
	"markTestActionResult"
)
const markTestActionError = defineCallableIPC<(sequenceId: string, id: string, error: string) => void>(
	"actionQueue",
	"markTestActionError"
)

class TestRunnerDebugger implements ExecutionDebugger {
	constructor(private sequenceId: string) {}

	markStart(id: string) {
		markTestActionStart(this.sequenceId, id)
	}

	markEnd(id: string) {
		markTestActionEnd(this.sequenceId, id)
	}
	logResult(id: string, result: any) {
		markTestActionResult(this.sequenceId, id, result)
	}
	logError(id: string, err: any) {
		markTestActionError(this.sequenceId, id, err instanceof Error ? err.message : String(err))
	}

	sequenceStarted() {
		markTestSequenceStart(this.sequenceId)
	}

	sequenceEnded() {
		markTestSequenceEnd(this.sequenceId)
	}
}

export const ActionQueueManager = Service(
	class {
		private testVMs = new Map<string, GraphVM>()

		constructor() {
			defineIPCFunc("actionQueue", "runTestSequence", (id: string, automation: AutomationData) => {
				this.runTestSequence(id, automation)
				return id
			})

			defineIPCFunc("actionQueue", "stopTestSequence", (id: string) => {
				return this.stopTestSequence(id)
			})
		}

		async queueOrRun(type: string, id: string, subId: string | undefined, contextData: object) {
			const resolver = ActionResolvers.getInstance().getResolver(type)
			if (!resolver) return

			const automation = resolver.getAutomation(id, subId)
			const contextSchema = await resolver.getContextSchema(id, subId)
			logger.log("QUEUE OR RUN", type, id, subId)
			const wrapper = resolver.getRunWrapper(id, subId)

			if (!automation) return
			if (!contextSchema) return

			if (automation.queue) {
				const queue = ActionQueue.storage.getById(automation.queue)

				if (!queue) return

				queue.enqueue({ type, id, subId }, serializeSchema(contextSchema, contextData))
			} else {
				if (!automation.graph) {
					logger.error("Automation missing graph — cannot execute", type, id, subId)
					return
				}

				const finalContext = await exposeSchema(contextSchema, contextData)
				const compiler = new GraphCompiler()
				const program = compiler.compile(automation.graph, automation.subgraphs, automation.dataWires)
				const vm = new GraphVM(program, { contextState: finalContext })
				await wrapper(async () => await vm.execute(), { type, id, subId })
			}
		}

		async runTestSequence(id: string, automation: AutomationData) {
			if (this.testVMs.has(id)) return

			let context: any = {}

			if (isTriggerData(automation) && automation.plugin && automation.trigger) {
				const triggerDef = PluginManager.getInstance().getTrigger(automation.plugin, automation.trigger)
				if (triggerDef) {
					const config = await deserializeSchema(triggerDef.config, automation.config)

					let contextSchema =
						typeof triggerDef.context != "function" ? triggerDef.context : await triggerDef.context(config)
					const defaultRunValues = automation.testContext
						? await deserializeSchema(contextSchema, automation.testContext)
						: {}

					await addDefaults(contextSchema, defaultRunValues)

					const exposedDefault = await exposeSchema(contextSchema, defaultRunValues)
					context = exposedDefault
				}
			}

			if (!automation.graph) {
				logger.error("Automation missing graph — cannot test-run")
				return
			}

			const compiler = new GraphCompiler()
			const program = compiler.compile(automation.graph, automation.subgraphs, automation.dataWires)
			const vm = new GraphVM(program, { contextState: context }, new TestRunnerDebugger(id))
			this.testVMs.set(id, vm)

			const runnerComplete = () => {
				this.testVMs.delete(id)
			}

			vm.execute().then(runnerComplete).catch(runnerComplete)
		}

		stopTestSequence(id: string) {
			const vm = this.testVMs.get(id)
			if (!vm) return false

			vm.abort()
			return true
		}
	}
)
