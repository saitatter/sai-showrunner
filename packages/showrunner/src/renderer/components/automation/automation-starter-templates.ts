import type { AutomationConfig, GraphNode } from "ShowRunner-schema"

export interface AutomationStarterTemplate {
	id: string
	name: string
	description: string
	icon: string
	create(): AutomationConfig
}

export const automationStarterTemplates: AutomationStarterTemplate[] = [
	{
		id: "youtube-paid-alert",
		name: "YouTube Paid Alert",
		description: "Super Chat or Super Sticker -> Paid Alert widget.",
		icon: "mdi mdi-youtube",
		create() {
			return createTemplate("YouTube Paid Alert", "youtube", "superChat", [
				actionNode("push-paid-alert", "overlays", "pushPaidAlert", 360, 120, {
					eventId: "{{ messageId }}",
					platform: "youtube",
					viewerName: "{{ viewerName }}",
					amount: "{{ amountMicros }}",
					currency: "{{ currency }}",
					title: "New Super Chat",
					message: "{{ message }}",
				}),
			])
		},
	},
	{
		id: "twitch-sub-paid-alert",
		name: "Twitch Sub Alert",
		description: "Subscription -> Paid Alert widget.",
		icon: "mdi mdi-star-outline",
		create() {
			return createTemplate("Twitch Sub Alert", "twitch", "subscription", [
				actionNode("push-paid-alert", "overlays", "pushPaidAlert", 360, 120, {
					eventId: "twitch-sub-{{ viewer }}-{{ totalMonths }}",
					platform: "twitch",
					viewerName: "{{ viewer }}",
					amount: "{{ totalMonths }} months",
					currency: "",
					title: "New Subscriber",
					message: "{{ message }}",
				}),
			])
		},
	},
	{
		id: "twitch-bits-paid-alert",
		name: "Twitch Bits Alert",
		description: "Bits cheered -> Paid Alert widget.",
		icon: "twi twi-bits",
		create() {
			return createTemplate("Twitch Bits Alert", "twitch", "bits", [
				actionNode("push-paid-alert", "overlays", "pushPaidAlert", 360, 120, {
					eventId: "twitch-bits-{{ viewer }}-{{ bits }}",
					platform: "twitch",
					viewerName: "{{ viewer }}",
					amount: "{{ bits }}",
					currency: "bits",
					title: "Bits Cheered",
					message: "{{ message }}",
				}),
			])
		},
	},
	{
		id: "starting-soon-scene-banner",
		name: "Starting Soon Scene Banner",
		description: "Starter graph that publishes a scene.begin banner.",
		icon: "mdi mdi-play-box-outline",
		create() {
			return createTemplate("Starting Soon Scene Banner", "ShowRunner", "autoRun", [
				actionNode("begin-scene", "overlays", "beginSceneOverlay", 360, 120, {
					sceneKey: "starting-soon",
					title: "Starting Soon",
					subtitle: "Stream begins shortly",
					accentColor: "#9146ff",
				}),
			])
		},
	},
	{
		id: "ending-scene-banner",
		name: "Ending Scene Banner",
		description: "Starter graph that publishes a scene.end banner after a closing message.",
		icon: "mdi mdi-stop-circle-outline",
		create() {
			return createTemplate("Ending Scene Banner", "ShowRunner", "autoRun", [
				actionNode("begin-scene", "overlays", "beginSceneOverlay", 360, 120, {
					sceneKey: "ending",
					title: "Thanks for watching",
					subtitle: "See you next stream",
					accentColor: "#64b5f6",
				}),
				actionNode("end-scene", "overlays", "endSceneOverlay", 640, 120, {
					sceneKey: "ending",
				}),
			], [
				{ id: "begin-scene:end-scene", from: "begin-scene", to: "end-scene" },
			])
		},
	},
]

function createTemplate(
	name: string,
	plugin: string,
	trigger: string,
	nodes: GraphNode[],
	edges = nodes.length > 1 ? nodes.slice(0, -1).map((node, index) => ({ id: `${node.id}:${nodes[index + 1].id}`, from: node.id, to: nodes[index + 1].id })) : []
): AutomationConfig {
	return {
		name,
		schemaVersion: 2,
		plugin,
		trigger,
		config: {},
		stop: false,
		graph: {
			nodes,
			edges,
			entryNodeId: nodes[0]?.id ?? "",
		},
		subgraphs: [],
		dataWires: [],
		variableNodes: [],
	}
}

function actionNode(
	id: string,
	plugin: string,
	action: string,
	x: number,
	y: number,
	config: Record<string, unknown>
): Extract<GraphNode, { type: "action" }> {
	return {
		id,
		type: "action",
		plugin,
		action,
		config,
		x,
		y,
	}
}
