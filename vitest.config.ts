import { defineConfig } from "vitest/config"

export default defineConfig({
	test: {
		include: ["libs/**/*.test.ts", "plugins/**/*.test.ts", "packages/**/*.test.ts"],
		environment: "node",
	},
	resolve: {
		alias: {
			ShowRunner_schema: "./libs/ShowRunner-schema/src",
		},
	},
})
