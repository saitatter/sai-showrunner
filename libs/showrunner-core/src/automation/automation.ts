import { AutomationConfig, createInlineAutomation } from "ShowRunner-schema"
import { FileResource } from "../resources/file-resource"
import { ResourceStorage } from "../resources/resource"
import { nanoid } from "nanoid/non-secure"
import { ActionResolvers } from "../queue-system/resolvers"

export class Automation extends FileResource<AutomationConfig> {
	static resourceDirectory: string = "./automations"
	static storage = new ResourceStorage<Automation>("Automation")

	constructor(name?: string) {
		super()

		if (name) {
			this._id = nanoid()
		}

		this._config = {
			name: name ?? "",
			...createInlineAutomation(),
		}

		this.state = {}
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
