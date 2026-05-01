import { AutomationConfig, ResourceData } from "castmate-schema"
import { App, computed, markRaw } from "vue"
import { nanoid } from "nanoid/non-secure"
import {
	AutomationView,
	ProjectGroup,
	ProjectItem,
	useDockingStore,
	useDocumentStore,
	useProjectStore,
	useResourceData,
	useResourceStore,
} from "../main"
import NameDialogVue from "../components/dialogs/NameDialog.vue"

export interface AutomationResourceView {
	automationView: AutomationView
}

export interface InlineAutomationView {
	open: boolean
	height: number
	automationView: AutomationView
}

export function createInlineAutomationView(): InlineAutomationView {
	return {
		open: false,
		height: 600,
		automationView: {
			panState: {
				zoomX: 4,
				zoomY: 1,
				panX: 0,
				panY: 0,
				panning: false,
			},
		},
	}
}

function createAutomationViewData(resource: ResourceData<AutomationConfig>): AutomationResourceView {
	return {
		automationView: {
			panState: {
				zoomX: 4,
				zoomY: 1,
				panX: 0,
				panY: 0,
				panning: false,
			},
		},
	}
}

function createAutomationGroup(app: App<Element>) {
	const resources = useResourceData<ResourceData<AutomationConfig>>("Automation")
	const resourceStore = useResourceStore()
	const dockingStore = useDockingStore()

	const group = computed<ProjectGroup>(() => {
		let items: ProjectItem[] = []

		if (resources.value) {
			const resourceItems = [...resources.value.resources.values()]

			resourceItems.sort((a, b) => a.config.name.localeCompare(b.config.name))

			items = resourceItems.map((r) => ({
				id: r.id,
				title: r.config.name,
				icon: `mdi mdi-cogs`,
				open() {
					dockingStore.openDocument(r.id, r.config, createAutomationViewData(r), "automation", "mdi mdi-cogs")
				},
				rename(name) {
					resourceStore.applyResourceConfig("Automation", r.id, { name })
				},
				delete() {
					resourceStore.deleteResource("Automation", r.id)
				},
			}))
		}

		const templateItems = automationTemplates.map((template) => ({
			id: `template:${template.id}`,
			title: template.title,
			icon: template.icon,
			async open() {
				const name = uniqueAutomationName(template.name, resources.value?.resources)
				const id = await resourceStore.createResource("Automation", name)
				const config = template.create(name)
				await resourceStore.setResourceConfig("Automation", id, config)
				dockingStore.openDocument(id, config, createAutomationViewData({ id, config, state: {} }), "automation", "mdi mdi-cogs")
			},
		}))

		return {
			id: "automation",
			title: "Automations",
			icon: "mdi mdi-cogs",
			items: [...templateItems, ...items],
			create() {
				const dialog = app.config.globalProperties.$dialog
				if (!resources.value) return
				dialog.open(NameDialogVue, {
					props: {
						header: `New Automation`,
						style: {
							width: "25vw",
						},
						modal: true,
					},
					onClose(options) {
						if (!options?.data) {
							return
						}

						resourceStore.createResource("Automation", options.data)
					},
				})
			},
		}
	})

	return group
}

interface AutomationTemplate {
	id: string
	title: string
	name: string
	icon: string
	create(name: string): AutomationConfig
}

function createAction(plugin: string, action: string, config: Record<string, unknown>, resultMapping?: Record<string, string>) {
	return {
		id: nanoid(),
		plugin,
		action,
		config,
		...(resultMapping ? { resultMapping } : {}),
	}
}

function approvedCondition() {
	return {
		type: "group",
		operator: "and",
		operands: [
			{
				id: nanoid(),
				type: "value",
				operator: "equal",
				lhs: { type: "value", schemaType: "Boolean", value: "{{ approved }}" },
				rhs: { type: "value", schemaType: "Boolean", value: true },
			},
		],
	}
}

function createModeratedChatTemplate(name: string, platform: "twitch" | "youtube"): AutomationConfig {
	const platformTitle = platform === "twitch" ? "Twitch" : "YouTube"
	return {
		name,
		plugin: platform,
		trigger: "chatMessage",
		config: {},
		sequence: {
			actions: [
				createAction(
					"moderation",
					"moderateChatMessage",
					{
						platform,
						messageId: "{{ messageId }}",
						viewerId: "{{ viewerId }}",
						viewerName: "{{ viewerName }}",
						message: "{{ message }}",
						badges: platform === "twitch" ? "{{ badges }}" : "",
						isModerator: "{{ isModerator }}",
						isMember: "{{ isMember }}",
						isOwner: "{{ isOwner }}",
					},
					{
						approved: "approved",
						blocked: "blocked",
						flagged: "flagged",
						verdict: "moderationVerdict",
						reason: "moderationReason",
						messageId: "moderatedMessageId",
					}
				),
				{
					id: nanoid(),
					plugin: "castmate",
					action: "branch",
					config: {},
					subFlows: [
						{
							id: nanoid(),
							config: { condition: approvedCondition() },
							actions: [
								createAction("overlays", "pushChatMessage", {
									messageId: "{{ moderatedMessageId }}",
									platform,
									viewerName: "{{ viewerName }}",
									message: "{{ message }}",
									badges: platform === "twitch" ? "{{ badges }}" : "",
								}),
							],
						},
					],
				},
			],
		},
		floatingSequences: [],
		testContext: {
			platform,
			viewerId: `${platform}-viewer-id`,
			viewerName: `${platformTitle} Viewer`,
			messageId: `${platform}-message-id`,
			message: `Hello from ${platformTitle}`,
			badges: "",
			isModerator: false,
			isMember: false,
			isOwner: false,
		},
	} as AutomationConfig
}

const automationTemplates: AutomationTemplate[] = [
	{
		id: "twitch-moderated-chat-feed",
		title: "Template: Twitch Moderated Chat Feed",
		name: "Twitch Moderated Chat Feed",
		icon: "mdi mdi-twitch",
		create: (name) => createModeratedChatTemplate(name, "twitch"),
	},
	{
		id: "youtube-moderated-chat-feed",
		title: "Template: YouTube Moderated Chat Feed",
		name: "YouTube Moderated Chat Feed",
		icon: "mdi mdi-youtube",
		create: (name) => createModeratedChatTemplate(name, "youtube"),
	},
	{
		id: "approved-only-chat-feed",
		title: "Template: Approved Only Chat Feed",
		name: "Approved Only Chat Feed",
		icon: "mdi mdi-chat-check",
		create(name) {
			return {
				name,
				sequence: {
					actions: [
						createAction("overlays", "pushChatMessage", {
							messageId: "{{ messageId }}",
							platform: "{{ platform }}",
							viewerName: "{{ viewerName }}",
							message: "{{ message }}",
							badges: "{{ badges }}",
						}),
					],
				},
				floatingSequences: [],
				testContext: {
					platform: "twitch",
					viewerName: "Approved Viewer",
					messageId: "approved-message-id",
					message: "Approved chat message",
					badges: "",
				},
			}
		},
	},
]

function uniqueAutomationName(name: string, resources?: Map<string, ResourceData<AutomationConfig>>) {
	if (!resources) return name
	let candidate = name
	let index = 2
	while ([...resources.values()].some((resource) => resource.config.name === candidate)) {
		candidate = `${name} ${index}`
		index += 1
	}
	return candidate
}

export function useOpenAutomationDocument() {
	const dockingStore = useDockingStore()
	const resourceStore = useResourceData<ResourceData<AutomationConfig>>("Automation")

	return (id: string) => {
		const resource = resourceStore.value?.resources?.get(id)
		if (!resource) return

		dockingStore.openDocument(
			resource.id,
			resource.config,
			createAutomationViewData(resource),
			"automation",
			"mdi mdi-cogs"
		)
	}
}

export async function initializeAutomations(app: App<Element>) {
	const documentStore = useDocumentStore()
	const resourceStore = useResourceStore()
	const projectStore = useProjectStore()

	documentStore.registerSaveFunction("automation", async (doc) => {
		await resourceStore.setResourceConfig("Automation", doc.id, doc.data)
	})

	projectStore.registerProjectGroupItem(createAutomationGroup(app))
}
