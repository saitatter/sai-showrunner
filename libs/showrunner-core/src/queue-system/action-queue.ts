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
} from "showrunner-schema"
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
import { compileAutomationProgram } from "../graph-engine/program-cache"
import { GraphVM } from "../graph-engine/vm"

const logger = usePluginLogger("queues")

export interface QueueAutomationEvent {
	queueId: string
	queueName: string
	itemId: string
	sourceType: string
	sourceId: string
	sourceSubId?: string
	payload: Record<string, any>
	queuedAt?: string
	startedAt: string
}

export class ActionQueue extends FileResource<ActionQueueConfig, ActionQueueState> {
	static resourceDirectory: string = "./queues"
	static storage = new ResourceStorage<ActionQueue>("ActionQueue")

	private activeVM: GraphVM | null = null
	private activeAbortController: AbortController | null = null
	private activeTimeout: NodeJS.Timeout | undefined = undefined
	private lastCompletion: number | null = null
	private scheduledId: string | undefined = undefined
	private scheduler: NodeJS.Timeout | undefined = undefined

	constructor(config?: ActionQueueConfig) {
		super()

		if (config) {
			this._id = nanoid()
			this._config = config
		} else {
			this._config = { name: "", paused: false, gap: 0, timeout: 30 }
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
		return !this.isRunning && this.scheduler == null
	}

	/**
	 * If a queue is paused it will finish running the current automation, but not start a new one.
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

	get timeout() {
		return this.config.timeout ?? 30
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
			this.activeAbortController?.abort()
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

	clearPending() {
		this.clearScheduled()
		this.state.queue.splice(0)
	}

	spliceQueue(index: number, deleteCount: number, ...items: QueuedAutomation[]) {
		this.state.queue.splice(index, deleteCount, ...items)
	}

	replay(id: string) {
		const played = this.state.history.find((i) => i.id == id)
		if (!played) return

		this.enqueue(played.source, played.queueContext.contextState)
	}

	private getNextAutomation(): QueuedAutomation | undefined {
		return this.state.queue.shift()
	}

	private async runNext() {
		if (this.activeVM || this.state.running) {
			return
		}

		const queueItem = this.getNextAutomation()

		if (!queueItem) return

		const resolver = ActionResolvers.getInstance().getResolver(queueItem.source.type)

		if (!resolver) return

		const automation = resolver.getAutomation(queueItem.source.id, queueItem.source.subId)
		const contextSchema = await resolver.getContextSchema(queueItem.source.id, queueItem.source.subId)
		const wrapper = resolver.getRunWrapper(queueItem.source.id, queueItem.source.subId)

		if (!automation) return
		if (!contextSchema) return

		const deserializedContext = await deserializeSchema(contextSchema, queueItem.queueContext.contextState)
		const finalContext = await exposeSchema(contextSchema, deserializedContext)

		if (!automation.graph) {
			logger.error("Automation missing graph — cannot execute", queueItem.source)
			this.pushToHistory(queueItem)
			return
		}

		const program = compileAutomationProgram(automation)
		const abortController = new AbortController()
		this.activeAbortController = abortController
		this.activeVM = new GraphVM(program, { contextState: finalContext }, undefined, abortController.signal)
		this.state.running = queueItem

		const doRun = async () => {
			try {
				ActionQueueManager.getInstance().emitQueueItemStarted(this, queueItem)
				const timeoutMs = Math.max(0, this.timeout * 1000)
				if (timeoutMs > 0) {
					this.activeTimeout = setTimeout(() => {
						logger.error("Queue automation timed out", queueItem.source, this.timeout)
						abortController.abort()
						this.activeVM?.abort()
					}, timeoutMs)
				}
				await wrapper(async () => await this.activeVM?.execute(), queueItem.source)
			} finally {
				if (this.activeTimeout) {
					clearTimeout(this.activeTimeout)
					this.activeTimeout = undefined
				}
				this.lastCompletion = Date.now()
				this.activeVM = null
				this.activeAbortController = null
				this.state.running = undefined
				this.pushToHistory(queueItem)
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

const markTestActionStart = defineCallableIPC<(executionId: string, id: string) => void>(
	"actionQueue",
	"markTestActionStart"
)
const markTestActionEnd = defineCallableIPC<(executionId: string, id: string) => void>(
	"actionQueue",
	"markTestActionEnd"
)
const markTestExecutionStart = defineCallableIPC<(executionId: string) => void>("actionQueue", "markTestExecutionStart")
const markTestExecutionEnd = defineCallableIPC<(executionId: string) => void>("actionQueue", "markTestExecutionEnd")
const markTestActionResult = defineCallableIPC<(executionId: string, id: string, result: any) => void>(
	"actionQueue",
	"markTestActionResult"
)
const markTestActionError = defineCallableIPC<(executionId: string, id: string, error: string) => void>(
	"actionQueue",
	"markTestActionError"
)

class TestRunnerDebugger implements ExecutionDebugger {
	constructor(private executionId: string) {}

	markStart(id: string) {
		markTestActionStart(this.executionId, id)
	}

	markEnd(id: string) {
		markTestActionEnd(this.executionId, id)
	}
	logResult(id: string, result: any) {
		markTestActionResult(this.executionId, id, result)
	}
	logError(id: string, err: any) {
		markTestActionError(this.executionId, id, err instanceof Error ? err.message : String(err))
	}

	executionStarted() {
		markTestExecutionStart(this.executionId)
	}

	executionEnded() {
		markTestExecutionEnd(this.executionId)
	}
}

export const ActionQueueManager = Service(
	class {
		private testVMs = new Map<string, GraphVM>()
		private queueItemStartedListeners = new Set<(event: QueueAutomationEvent) => void | Promise<void>>()

		constructor() {
			defineIPCFunc("actionQueue", "runTestExecution", (id: string, automation: AutomationData) => {
				this.runTestExecution(id, automation)
				return id
			})

			defineIPCFunc("actionQueue", "stopTestExecution", (id: string) => {
				return this.stopTestExecution(id)
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
				const program = compileAutomationProgram(automation)
				const vm = new GraphVM(program, { contextState: finalContext })
				await wrapper(async () => await vm.execute(), { type, id, subId })
			}
		}

		onQueueItemStarted(listener: (event: QueueAutomationEvent) => void | Promise<void>) {
			this.queueItemStartedListeners.add(listener)
			return () => {
				this.queueItemStartedListeners.delete(listener)
			}
		}

		emitQueueItemStarted(queue: ActionQueue, item: QueuedAutomation) {
			const context = item.queueContext.contextState ?? {}
			const payload = context.payload && typeof context.payload === "object" ? context.payload : context
			const event: QueueAutomationEvent = {
				queueId: queue.id,
				queueName: queue.config.name,
				itemId: item.id,
				sourceType: item.source.type,
				sourceId: item.source.id,
				sourceSubId: item.source.subId,
				payload,
				queuedAt: typeof context.queuedAt === "string" ? context.queuedAt : undefined,
				startedAt: new Date().toISOString(),
			}

			for (const listener of this.queueItemStartedListeners) {
				void Promise.resolve(listener(event)).catch((error) => {
					logger.error("Queue item started listener failed", error)
				})
			}
		}

		async runTestExecution(id: string, automation: AutomationData) {
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

			const program = compileAutomationProgram(automation)
			const vm = new GraphVM(program, { contextState: context }, new TestRunnerDebugger(id))
			this.testVMs.set(id, vm)

			const runnerComplete = () => {
				this.testVMs.delete(id)
			}

			vm.execute().then(runnerComplete).catch(runnerComplete)
		}

		stopTestExecution(id: string) {
			const vm = this.testVMs.get(id)
			if (!vm) return false

			vm.abort()
			return true
		}
	}
)
