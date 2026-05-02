import { defineConfig } from "vitest/config"

export default defineConfig({
	test: {
		include: ["libs/**/*.test.ts", "plugins/**/*.test.ts"],
		environment: "node",
	},
	resolve: {
		alias: {
			castmate_schema: "./libs/castmate-schema/src",
		},
	},
})
