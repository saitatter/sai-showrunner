import {
	defineAction,
	defineTrigger,
	onLoad,
	onUnload,
	definePlugin,
	useHTTPRouter,
	onProfilesChanged,
	resetRouter,
	coreAxios,
} from "castmate-core"
import axios from "axios"

export default definePlugin(
	{
		id: "http",
		name: "HTTP",
		description: "UI Description",
		icon: "mdi mdi-web",
		color: "#9E436E",
	},
	() => {
		const endpointRoutes = useHTTPRouter("endpoints")

		defineAction({
			id: "request",
			name: "HTTP Request",
			icon: "mdi mdi-web",
			config: {
				type: Object,
				properties: {
					method: {
						type: String,
						name: "Method",
						enum: ["GET", "POST", "DELETE", "PUT", "PATCH"],
						required: true,
						default: "GET",
					},
					url: {
						type: String,
						template: true,
						name: "URL",
						required: true,
					},
					query: {
						type: String,
						template: true,
						name: "Query String",
						required: false,
					},
					headers: {
						type: String,
						template: true,
						name: "Headers (JSON)",
						required: false,
					},
					body: {
						type: String,
						template: true,
						name: "Body",
						required: false,
					},
					contentType: {
						type: String,
						name: "Content Type",
						enum: ["application/json", "application/x-www-form-urlencoded", "text/plain"],
						required: false,
						default: "application/json",
					},
				},
			},
			result: {
				type: Object,
				properties: {},
			},
			async invoke(config, contextData, abortSignal) {
				let url = config.url
				if (config.query) {
					const separator = url.includes("?") ? "&" : "?"
					url = `${url}${separator}${config.query}`
				}

				let headers: Record<string, string> = {}
				if (config.headers) {
					try {
						headers = JSON.parse(config.headers)
					} catch {
						throw new Error("Headers must be valid JSON")
					}
				}

				if (config.body && config.contentType) {
					headers["content-type"] ??= config.contentType
				}

				const resp = await coreAxios.request({
					method: config.method,
					url,
					headers: Object.keys(headers).length > 0 ? headers : undefined,
					data: config.body || undefined,
				})

				return resp.data
			},
		})

		const endpointTrigger = defineTrigger({
			id: "endpoint",
			name: "HTTP Endpoint",
			icon: "mdi mdi-server-network",
			description: "Responds to incoming HTTP requests at /plugins/endpoints/...",
			config: {
				type: Object,
				properties: {
					method: {
						type: String,
						name: "Method",
						enum: ["GET", "POST", "DELETE", "PUT", "PATCH"],
						default: "POST",
						required: true,
					},
					route: {
						type: String,
						name: "Route",
						required: true,
					},
				},
			},
			context: {
				type: Object,
				properties: {
					method: { type: String, name: "Method", required: true, view: false },
					route: { type: String, name: "Route", required: true, view: false },
					params: { type: Object, name: "URL Params", required: true, properties: {} },
					query: { type: Object, name: "Query Params", required: true, properties: {} },
					body: { type: Object, name: "Request Body", required: true, properties: {} },
				},
			},
			async handle(config, context, mapping) {
				return config.method == context.method && config.route == context.route
			},
		})

		onProfilesChanged((activeProfiles, inactiveProfiles) => {
			resetRouter(endpointRoutes)

			const routes: Record<string, Set<string>> = {
				GET: new Set<string>(),
				POST: new Set<string>(),
				DELETE: new Set<string>(),
				PUT: new Set<string>(),
				PATCH: new Set<string>(),
			}

			for (const profile of activeProfiles) {
				for (const trigger of profile.iterTriggers(endpointTrigger)) {
					const routeName = trigger.config.route

					routes[trigger.config.method]?.add(routeName)
				}
			}

			for (const method in routes) {
				for (const route of routes[method]) {
					endpointRoutes[method.toLowerCase() as "get" | "post" | "delete" | "put" | "patch"]?.(
						route,
						(req, res, next) => {
							endpointTrigger({
								method,
								route,
								params: req.params,
								query: req.query || {},
								body: req.body || {},
							})
							res.status(201).end()
							next()
						}
					)
				}
			}
		})
	}
)
