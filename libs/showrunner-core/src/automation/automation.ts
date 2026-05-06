import { AutomationConfig, createInlineAutomation, normalizeAutomationConfig } from "showrunner-schema"
import { FileResource } from "../resources/file-resource"
import { ResourceStorage } from "../resources/resource"
import { normalizeRequiredResourceName } from "../resources/resource-name"
import { nanoid } from "nanoid/non-secure"
import { ActionResolvers } from "../queue-system/resolvers"
import { validateAutomationProgram } from "../graph-engine/program-cache"

export class Automation extends FileResource<AutomationConfig> {
	static resourceDirectory: string = "./automations"
	static storage = new ResourceStorage<Automation>("Automation")

	constructor(name?: string) {
		super()

		if (name !== undefined) {
			name = normalizeRequiredResourceName(name, "Automation name")
			this._id = nanoid()
		}

		this._config = {
			name: name ?? "",
			...createInlineAutomation(),
		}

		this.state = {}
	}

	async load(savedConfig: object): Promise<boolean> {
		const before = JSON.stringify(savedConfig)
		const normalized = normalizeAutomationConfig(savedConfig as Partial<AutomationConfig>)
		validateAutomationProgram(normalized)
		const result = await super.load(normalized)
		if (JSON.stringify(normalized) !== before) {
			await this.save()
		}
		return result
	}

	async setConfig(config: AutomationConfig): Promise<boolean> {
		const normalized = normalizeAutomationConfig(config)
		normalized.name = normalizeRequiredResourceName(normalized.name?.trim() || this.config?.name || "Untitled Automation", "Automation name")
		validateAutomationProgram(normalized)
		return super.setConfig(normalized)
	}

	async applyConfig(config: Partial<AutomationConfig>): Promise<boolean> {
		if ("name" in config) {
			config = { ...config, name: normalizeRequiredResourceName(config.name, "Automation name") }
		}
		const normalized = normalizeAutomationConfig({ ...this.config, ...config })
		validateAutomationProgram(normalized)
		return super.setConfig(normalized)
	}
}

export async function setupAutomations() {
	await Automation.initialize()

	ActionResolvers.getInstance().registerResolver("automation", {
		getAutomation(id) {
			return Automation.storage.getById(id)?.config
		},

		async getContextSchema() {
			return {
				type: Object,
				properties: {
					payload: { type: Object, name: "Payload" },
					queuedAt: { type: String, name: "Queued At" },
					source: { type: Object, name: "Source" },
				},
			}
		},

		getRunWrapper() {
			return async (inner) => await inner()
		},
	})
}
