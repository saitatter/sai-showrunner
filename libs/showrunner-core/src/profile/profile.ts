import {
	ProfileState,
	ProfileConfig,
	TriggerData,
	AutomationTriggerNode,
	Schema,
	SchemaType,
	createInlineAutomation,
	AutomationGraph,
	normalizeInlineAutomation,
} from "showrunner-schema"
import { Resource, ResourceStorage } from "../resources/resource"
import { normalizeRequiredResourceName } from "../resources/resource-name"
import { FileResource } from "../resources/file-resource"
import { nanoid } from "nanoid/non-secure"
import { evaluateBooleanExpression } from "../util/boolean-helpers"
import { ReactiveEffect, autoRerun } from "../reactivity/reactivity"
import { ProfileManager } from "./profile-system"
import { TriggerFunc } from "../queue-system/trigger"
import { PluginManager } from "../plugins/plugin-manager"
import { ActionResolvers } from "../queue-system/resolvers"
import { isFunction, now } from "lodash"
import { usePluginLogger } from "../logging/logging"

export class Profile extends FileResource<ProfileConfig, ProfileState> {
	static resourceDirectory: string = "./profiles"
	static storage = new ResourceStorage<Profile>("Profile")

	private stateEffect: ReactiveEffect | undefined

	constructor(name?: string) {
		super()

		const normalizedName = name !== undefined
			? normalizeRequiredResourceName(name, "Profile name")
			: undefined
		if (name !== undefined) {
			this._id = nanoid()
		}

		this._config = {
			name: normalizedName ?? "",
			activationMode: "toggle",
			triggers: [],
			activationCondition: {
				type: "group",
				operator: "or",
				operands: [],
			},
			activationAutomation: createInlineAutomation(),
			deactivationAutomation: createInlineAutomation(),
		}

		this.state = {
			active: false,
		}
	}

	async load(savedConfig: object): Promise<boolean> {
		const before = JSON.stringify(savedConfig)
		const normalized = normalizeProfileConfig(savedConfig as Partial<ProfileConfig>)
		const result = await super.load(normalized)
		if (JSON.stringify(normalized) !== before) {
			await this.save()
		}
		await this.setupReactivity()
		return result
	}

	async setConfig(config: ProfileConfig): Promise<boolean> {
		config = { ...config, name: normalizeProfileName(config.name, this.config?.name) }
		const result = await super.setConfig(config)
		await this.setupReactivity()
		return result
	}

	async applyConfig(config: Partial<ProfileConfig>): Promise<boolean> {
		const merged = { ...this.config, ...config, name: normalizeProfileName(config.name, this.config?.name) }
		const result = await super.setConfig(merged)
		await this.setupReactivity()
		return result
	}

	static async onCreate(profile: Profile) {
		await super.onCreate(profile)
		await profile.setupReactivity()
		ProfileManager.getInstance().signalProfilesChanged()
	}

	static async onDelete(profile: Profile) {
		await super.onDelete(profile)
		profile.stopAutoActivate()
		ProfileManager.getInstance().signalProfilesChanged()
	}

	async forceActivationRecompute() {
		await this.setupReactivity()
	}

	private stopAutoActivate() {
		if (this.stateEffect) {
			this.stateEffect.dispose()
			this.stateEffect = undefined
		}
	}

	private async setupReactivity() {
		this.stopAutoActivate()

		this.stateEffect = await autoRerun(async () => {
			if (this.config.activationMode == "toggle") {
				const activationResult = await evaluateBooleanExpression(this.config.activationCondition)
				this.state.active = activationResult
			} else {
				this.state.active = this.config.activationMode
			}
			ProfileManager.getInstance()?.signalProfilesChanged()
		})
	}

	getGraph(id: string): AutomationGraph | undefined {
		if (id == "activation") return this.config.activationAutomation.graph
		if (id == "deactivation") return this.config.deactivationAutomation.graph

		const trigger = this.config.triggers.find((t) => t.id == id)
		if (trigger) {
			return trigger.graph
		}
		return undefined
	}

	getTrigger(id: string) {
		const triggerData = this.config.triggers.find((t) => t.id == id)
		if (!triggerData?.plugin || !triggerData?.trigger) return undefined
		return PluginManager.getInstance().getPlugin(triggerData.plugin)?.triggers?.get(triggerData.trigger)
	}

	*iterTriggers<Config extends Schema, ContextData extends Schema, InvokeContextData extends Schema>(
		trigger: TriggerFunc<Config, ContextData, InvokeContextData>
	): IterableIterator<TriggerData<SchemaType<Config>>> {
		for (const t of this.config.triggers) {
			const triggerNodes = Array.isArray(t.triggerNodes) ? t.triggerNodes : []
			if (triggerNodes.length) {
				for (const triggerNode of triggerNodes) {
					if (triggerNode.plugin != trigger.triggerDef.pluginId || triggerNode.trigger != trigger.triggerDef.id) continue
					yield createGraphTriggerInvocation(t, triggerNode) as TriggerData<SchemaType<Config>>
				}
				continue
			}
			if (t.plugin == trigger.triggerDef.pluginId && t.trigger == trigger.triggerDef.id) {
				yield t as TriggerData<SchemaType<Config>>
			}
		}
	}
}

function normalizeProfileName(name: string | undefined, fallback: string | undefined) {
	return normalizeRequiredResourceName(name?.trim() || fallback || "Untitled Profile", "Profile name")
}

const GRAPH_TRIGGER_SUB_ID_PREFIX = "__graphTrigger:"

function createGraphTriggerInvocation(parent: TriggerData, triggerNode: AutomationTriggerNode): TriggerData {
	return {
		...parent,
		id: triggerNode.id,
		plugin: triggerNode.plugin,
		trigger: triggerNode.trigger,
		config: triggerNode.config,
		stop: triggerNode.stop ?? parent.stop,
		automationSubId: makeGraphTriggerSubId(parent.id, triggerNode.id),
	} as TriggerData & { automationSubId: string }
}

function makeGraphTriggerSubId(automationId: string, triggerNodeId: string) {
	return `${GRAPH_TRIGGER_SUB_ID_PREFIX}${encodeURIComponent(automationId)}:${encodeURIComponent(triggerNodeId)}`
}

function parseGraphTriggerSubId(subId: string | undefined) {
	if (!subId?.startsWith(GRAPH_TRIGGER_SUB_ID_PREFIX)) return undefined
	const body = subId.slice(GRAPH_TRIGGER_SUB_ID_PREFIX.length)
	const separator = body.indexOf(":")
	if (separator < 0) return undefined
	return {
		automationId: decodeURIComponent(body.slice(0, separator)),
		triggerNodeId: decodeURIComponent(body.slice(separator + 1)),
	}
}

function normalizeProfileConfig(config: Partial<ProfileConfig>): ProfileConfig {
	const base = config as ProfileConfig
	base.triggers = Array.isArray(base.triggers) ? base.triggers.map((trigger) => normalizeInlineAutomation(trigger as any) as TriggerData) : []
	base.activationAutomation = normalizeInlineAutomation((base.activationAutomation ?? createInlineAutomation()) as any)
	base.deactivationAutomation = normalizeInlineAutomation((base.deactivationAutomation ?? createInlineAutomation()) as any)
	return base
}

function getProfileTriggerTarget(profile: Profile, subId: string) {
	const graphTrigger = parseGraphTriggerSubId(subId)
	if (graphTrigger) {
		const automation = profile.config.triggers.find((trigger) => trigger.id === graphTrigger.automationId)
		const triggerNode = automation?.triggerNodes?.find((node) => node.id === graphTrigger.triggerNodeId)
		return automation && triggerNode ? { automation, triggerNode } : undefined
	}

	const automation = profile.config.triggers.find((trigger) => trigger.id == subId)
	return automation ? { automation } : undefined
}

const logger = usePluginLogger("profiles")

export async function setupProfiles() {
	await Profile.initialize()

	ActionResolvers.getInstance().registerResolver("profile", {
		getAutomation(id, subId) {
			if (!subId) return undefined

			const profile = Profile.storage.getById(id)

			if (!profile) return undefined

			if (subId == "activation") return profile.config.activationAutomation
			if (subId == "deactivation") return profile.config.deactivationAutomation

			return getProfileTriggerTarget(profile, subId)?.automation
		},

		async getContextSchema(id, subId) {
			if (!subId) return undefined

			const profile = Profile.storage.getById(id)
			if (!profile) return undefined

			if (subId == "activation") return { type: Object, properties: {} }
			if (subId == "deactivation") return { type: Object, properties: {} }

			const target = getProfileTriggerTarget(profile, subId)
			const trigger = target?.triggerNode ?? target?.automation
			if (!trigger) return undefined
			if (!trigger.trigger) return undefined
			if (!trigger.plugin) return undefined

			const triggerDef = PluginManager.getInstance().getTrigger(trigger.plugin, trigger.trigger)
			if (!triggerDef) return undefined

			if (isFunction(triggerDef.context)) {
				return await triggerDef.context(trigger.config)
			} else {
				return triggerDef.context
			}
		},

		getRunWrapper(id, subId) {
			const noWrap = async (inner: () => any) => await inner()

			if (!subId) return noWrap

			const profile = Profile.storage.getById(id)
			if (!profile) {
				//logger.log("Failed RunWrapper, MISSING PROFILE")
				return noWrap
			}

			const target = getProfileTriggerTarget(profile, subId)
			const trigger = target?.triggerNode ?? target?.automation
			if (!trigger) {
				//logger.log("Failed RunWrapper, MISSING TRIGGER", subId)
				return noWrap
			}
			if (!trigger.trigger) {
				//logger.log("Failed RunWrapper, MISSING TRIGGER DATA")
				return noWrap
			}
			if (!trigger.plugin) {
				//logger.log("Failed RunWrapper, MISSING PROFILE DATA")
				return noWrap
			}

			const triggerDef = PluginManager.getInstance().getTrigger(trigger.plugin, trigger.trigger)
			if (!triggerDef) {
				//logger.log("Failed RunWrapper, MISSING TRIGGER DEF")
				return noWrap
			}

			if (!triggerDef.runWrapper) {
				//logger.log("Failed RunWrapper, TriggerDef has no runwrapper", triggerDef.id)
				return noWrap
			}

			return triggerDef.runWrapper
		},

		getProgramOptions(id, subId) {
			if (!subId) return {}
			const profile = Profile.storage.getById(id)
			if (!profile) return {}
			const target = getProfileTriggerTarget(profile, subId)
			return target?.triggerNode ? { entryNodeId: target.triggerNode.id } : {}
		},
	})
}
