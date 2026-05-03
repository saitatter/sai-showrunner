import { BooleanExpression, constructDefault, Toggle, hashString } from "ShowRunner-schema"
import {
	ActionQueue,
	ActionQueueManager,
	Automation,
	Profile,
	ReactiveEffect,
	WebService,
	defineAction,
	definePlugin,
	defineSetting,
	defineTrigger,
	forceRunWithEffect,
	onLoad,
	onProfilesChanged,
	runOnChange,
	evaluateBooleanExpression,
	defineFlowAction,
	globalLogger,
	usePluginLogger,
	GraphVM,
	compileAutomationProgram,
} from "ShowRunner-core"
import { getExpressionHash } from "ShowRunner-core/src/util/boolean-helpers"

interface ConditionalTrigger {
	conditionHash: number
	lastEval: boolean | undefined
	effect: ReactiveEffect
}

export default definePlugin(
	{
		id: "ShowRunner",
		name: "ShowRunner",
		icon: "mdi mdi-webcam",
		color: "#DE84FF",
		description: "Builtin Actions and Triggers",
	},
	() => {
		const logger = usePluginLogger()

		const port = defineSetting("port", {
			type: Number,
			required: true,
			default: 8181,
			min: 1,
			max: 65535,
			name: "Internal Webserver Port",
		})

		onLoad(() => {
			WebService.getInstance().startHttp(port.value)
		})

		runOnChange(
			() => port.value,
			() => {
				WebService.getInstance().updatePort(port.value)
			}
		)

		defineAction({
			id: "addToQueue",
			name: "Add to Queue",
			icon: "mdi mdi-tray-plus",
			description: "Schedules another automation to run through a queue.",
			config: {
				type: Object,
				properties: {
					queue: { type: ActionQueue, name: "Queue", required: true },
					automation: { type: Automation, name: "Worker Automation", required: true },
					payload: { type: Object, name: "Payload" },
				},
			},
			result: {
				type: Object,
				properties: {
					queued: { type: Boolean, name: "Queued" },
					queueId: { type: String, name: "Queue ID" },
					automationId: { type: String, name: "Automation ID" },
				},
			},
			async invoke(config, contextData, abortSignal) {
				if (!config.queue || !config.automation) {
					return { queued: false, queueId: "", automationId: "" }
				}

				const payload =
					config.payload && Object.keys(config.payload).length > 0
						? config.payload
						: contextData.contextState

				config.queue.enqueue(
					{ type: "automation", id: config.automation.id },
					{
						payload,
						queuedAt: new Date().toISOString(),
						source: {
							type: "graph",
							action: "addToQueue",
						},
					}
				)

				return { queued: true, queueId: config.queue.id, automationId: config.automation.id }
			},
		})

		defineAction({
			id: "completeQueueItem",
			name: "Complete Queue Item",
			icon: "mdi mdi-check-circle-outline",
			description: "Marks the intended completion point of a queue worker graph. Queue items complete automatically when the graph ends.",
			config: {
				type: Object,
				properties: {},
			},
			result: {
				type: Object,
				properties: {
					completed: { type: Boolean, name: "Completed" },
				},
			},
			async invoke(config, contextData, abortSignal) {
				return { completed: true }
			},
		})

		defineAction({
			id: "cancelQueueItem",
			name: "Cancel Queue Item",
			icon: "mdi mdi-cancel",
			description: "Cancels the currently running queue item.",
			config: {
				type: Object,
				properties: {
					queue: { type: ActionQueue, name: "Queue", required: true },
				},
			},
			async invoke(config, contextData, abortSignal) {
				const runningId = config.queue?.state?.running?.id
				if (runningId) {
					config.queue.skip(runningId)
				}
			},
		})

		defineAction({
			id: "clearQueue",
			name: "Clear Queue",
			icon: "mdi mdi-tray-remove",
			description: "Clears pending queue items without interrupting the currently running item.",
			config: {
				type: Object,
				properties: {
					queue: { type: ActionQueue, name: "Queue", required: true },
				},
			},
			async invoke(config, contextData, abortSignal) {
				config.queue?.clearPending()
			},
		})

		const queueItemStarted = defineTrigger({
			id: "queueItemStarted",
			name: "Queue Item Started",
			icon: "mdi mdi-tray-arrow-down",
			description: "Runs when a queue worker item starts. Use it to drive queued alert or scene graphs.",
			config: {
				type: Object,
				properties: {
					queue: { type: ActionQueue, name: "Queue" },
				},
			},
			context: {
				type: Object,
				properties: {
					queueId: { type: String, name: "Queue ID" },
					queueName: { type: String, name: "Queue Name" },
					itemId: { type: String, name: "Queue Item ID" },
					sourceType: { type: String, name: "Source Type" },
					sourceId: { type: String, name: "Source ID" },
					sourceSubId: { type: String, name: "Source Sub ID" },
					payload: { type: Object, name: "Payload" },
					queuedAt: { type: String, name: "Queued At" },
					startedAt: { type: String, name: "Started At" },
				},
			},
			async handle(config, context) {
				if (!config.queue) return true
				return config.queue.id === context.queueId
			},
		})

		onLoad(() => {
			ActionQueueManager.getInstance().onQueueItemStarted((event) => queueItemStarted(event))
		})

		defineAction({
			id: "skip",
			name: "Queue Skip",
			icon: "mdi mdi-skip-next",
			config: {
				type: Object,
				properties: {
					queue: { type: ActionQueue, name: "Queue", required: true },
				},
			},
			async invoke(config, contextData, abortSignal) {
				const runningId = config.queue?.state?.running?.id
				if (runningId) {
					config.queue.skip(runningId)
				}
			},
		})

		defineAction({
			id: "pause",
			name: "Pause Queue",
			icon: "mdi mdi-swap-horizontal",
			config: {
				type: Object,
				properties: {
					queue: { type: ActionQueue, name: "Queue", required: true },
					paused: {
						type: Toggle,
						name: "Paused",
						required: true,
						trueIcon: "mdi mdi-pause",
						falseIcon: "mdi mdi-play",
						default: true,
					},
				},
			},
			async invoke(config, contextData, abortSignal) {
				let newPaused = config.paused as Toggle
				if (newPaused == "toggle") {
					newPaused = !config.queue.isPaused
				}
				config.queue.applyConfig({
					paused: newPaused,
				})
			},
		})

		defineAction({
			id: "profileActivation",
			name: "Profile Activation",
			icon: "mdi mdi-cogs",
			description: "Sets a profile's activation mode",
			config: {
				type: Object,
				properties: {
					profile: { type: Profile, name: "Profile", required: true },
					activation: {
						type: Toggle,
						name: "Activation Mode",
						required: true,
						default: true,
						toggleIcon: "mdi mdi-cogs",
					},
				},
			},
			async invoke(config, contextData, abortSignal) {
				await config.profile?.applyConfig({
					activationMode: config.activation,
				})
			},
		})

		defineAction({
			id: "toggleProfileActivation",
			name: "Toggle Profile Activation",
			icon: "mdi mdi-cogs",
			description: "Toggle's a Profile's Activation Mode",
			config: {
				type: Object,
				properties: {
					profile: { type: Profile, name: "Profile", required: true },
				},
			},
			async invoke(config, contextData, abortSignal) {
				if (!config.profile) return

				const mode = !config.profile.state.active

				await config.profile?.applyConfig({
					activationMode: mode,
				})
			},
		})

		//TODO: Detect length of automation
		defineAction({
			id: "runAutomation",
			name: "Run Automation",
			icon: "mdi mdi-cogs",
			description: "Runs an automation",
			config: {
				type: Object,
				properties: {
					automation: { type: Automation, name: "Automation", required: true },
				},
			},
			async invoke(config, contextData, abortSignal) {
				if (!config.automation.config.graph) return

				const program = compileAutomationProgram(config.automation.config)
				const vm = new GraphVM(program, contextData, undefined, abortSignal)

				const onabort = () => vm.abort()
				abortSignal.addEventListener("abort", onabort, { once: true })

				await vm.execute()

				abortSignal.removeEventListener("abort", onabort)
			},
		})

		const autoRunners = new Map<
			string,
			{
				triggerHash: number
				effect: ReactiveEffect
			}
		>()

		const autoRun = defineTrigger({
			id: "autoRun",
			name: "Run On Change",
			icon: "mdi mdi-cogs",
			description: "Automatically triggers when the values it uses changes.",
			config: {
				type: Object,
				properties: {},
			},
			context: {
				type: Object,
				properties: {
					triggerId: { type: String, required: true, view: false },
					profileId: { type: String, required: true, view: false },
				},
			},
			async handle(config, context, mapping) {
				if (mapping.profileId != context.profileId) return false
				if (mapping.triggerId != context.triggerId) return false
				return true
			},
			async runWrapper(inner, mapping) {
				const key = `${mapping.id}.${mapping.subId}`
				const runner = autoRunners.get(key)

				try {
					//logger.log("AutoRun Starting")
					if (runner) {
						await forceRunWithEffect(runner.effect, inner)
					} else {
						return await inner()
					}
				} finally {
					//logger.log("AutoRun Ending")
				}
			},
		})

		onProfilesChanged((active, inactive) => {
			for (const profile of active) {
				for (const trigger of profile.iterTriggers(autoRun)) {
					const key = `${profile.id}.${trigger.id}`

					const existing = autoRunners.get(key)
					const hash = hashString(JSON.stringify(trigger.graph ?? {}))
					if (!existing) {
						const effect = new ReactiveEffect(async () => {
							logger.log("RUN!")
							await autoRun({
								profileId: profile.id,
								triggerId: trigger.id,
							})
						})
						effect.debug = true
						effect.debugName = `autorun:${profile.id}.${trigger.id}`
						autoRunners.set(key, {
							triggerHash: hash,
							effect,
						})
						effect.run()
					} else {
						if (hash != existing.triggerHash) {
							existing.triggerHash = hash
							existing.effect.trigger()
						}
					}
				}
			}

			for (const profile of inactive) {
				for (const trigger of profile.iterTriggers(autoRun)) {
					const key = `${profile.id}.${trigger.id}`
					const existing = autoRunners.get(key)
					if (existing) {
						existing.effect.dispose()
						autoRunners.delete(key)
					}
				}
			}
		})

		const conditonalRunners = new Map<string, ConditionalTrigger>()

		const conditional = defineTrigger({
			id: "condition",
			name: "Condition",
			icon: "mdi mdi-cogs",
			config: {
				type: Object,
				properties: {
					condition: { type: BooleanExpression, name: "Condition" },
					runImmediately: { type: Boolean, name: "Run On Enable", required: true, default: false },
				},
			},
			context: {
				type: Object,
				properties: {
					triggerId: { type: String, required: true, view: false },
					profileId: { type: String, required: true, view: false },
				},
			},
			async handle(config, context, mapping) {
				if (mapping.profileId != context.profileId) return false
				if (mapping.triggerId != context.triggerId) return false
				return true
			},
		})

		onProfilesChanged((active, inactive) => {
			for (const profile of active) {
				for (const trigger of profile.iterTriggers(conditional)) {
					const key = `${profile.id}.${trigger.id}`

					const existing = conditonalRunners.get(key)
					const hash = getExpressionHash(trigger.config.condition)
					if (!existing) {
						const conditionalTrigger: ConditionalTrigger = {
							conditionHash: hash,
							lastEval: trigger.config.runImmediately ? false : undefined,
							effect: new ReactiveEffect(async () => {
								const result = await evaluateBooleanExpression(trigger.config.condition)
								if (conditionalTrigger.lastEval === undefined) {
									//If lastEval is undefined then we ignore the first eval, which will be at creation time.
									//This way if the trigger is enabled and the condition is true, it won't fire on the enable.
									conditionalTrigger.lastEval = result
								}

								if (result && !conditionalTrigger.lastEval) {
									//Rising edge, run trigger
									conditional({
										triggerId: trigger.id,
										profileId: profile.id,
									})
								}
								conditionalTrigger.lastEval = result
							}),
						}

						conditonalRunners.set(key, conditionalTrigger)
						conditionalTrigger.effect.run()
					} else {
						if (hash != existing.conditionHash) {
							existing.conditionHash = hash
							existing.effect.trigger()
						}
					}
				}
			}

			for (const profile of inactive) {
				for (const trigger of profile.iterTriggers(conditional)) {
					const key = `${profile.id}.${trigger.id}`
					const existing = conditonalRunners.get(key)
					if (existing) {
						existing.effect.dispose()
						conditonalRunners.delete(key)
					}
				}
			}
		})

		defineFlowAction({
			id: "branch",
			name: "Branch",
			icon: "mdi mdi-source-branch",
			config: { type: Object, properties: {} },
			flowConfig: {
				type: Object,
				properties: {
					condition: { type: BooleanExpression, name: "Condition", required: true },
				},
			},
			async invoke(config, flows, contextData, abortSignal) {
				//globalLogger.log("Invoking Branch", contextData.contextState, flows)
				for (const [key, flow] of Object.entries(flows)) {
					//globalLogger.log("Eval Condition", flow.condition)
					if (await evaluateBooleanExpression(flow.condition, contextData.contextState)) {
						//globalLogger.log("Condition True", key)
						return key
					}
				}
			},
		})
	}
)
