import { defineConfig } from "vite"
import vue from "@vitejs/plugin-vue"
import dts from "vite-plugin-dts"
import { libraryPlugin } from "showrunner-vite"

// https://vitejs.dev/config/
export default defineConfig({
	plugins: [
		vue(),
		dts({
			insertTypesEntry: true,
		}),
		libraryPlugin("showrunner-ui-core"),
	],
	build: {
		cssCodeSplit: true,
		lib: {
			entry: "src/main.ts",
			name: "showrunner-plugin-sound-renderer",
		},
		rollupOptions: {
			external: ["vue"],
			output: {
				exports: "named",
				globals: {
					vue: "Vue",
				},
			},
		},
	},
})
