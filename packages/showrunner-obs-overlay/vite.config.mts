import { defineConfig } from "vite"
import path from "path"
import { fileURLToPath } from "node:url"

const dirname = path.dirname(fileURLToPath(import.meta.url))
const dist = path.join(dirname, "dist")

export default defineConfig({
	base: "/overlays/",
	resolve: {
		alias: {
			path: "path-browserify",
		},
	},
	build: {
		outDir: path.join(dist, "obs-overlay"),
		minify: false,
		rollupOptions: {
			input: {
				main: path.resolve(dirname, "overlay.html"),
			},
		},
	},
})
