import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"
import { spawnSync } from "node:child_process"
import { deflateSync, inflateSync } from "node:zlib"
import { expect, it } from "vitest"

const repositoryRoot = resolve(import.meta.dirname, "../..")
function chunk(type, data) {
	const body = Buffer.concat([Buffer.from(type), data])
	let crc = 0xffffffff
	for (const byte of body) {
		crc ^= byte
		for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0)
	}
	const length = Buffer.alloc(4), checksum = Buffer.alloc(4)
	length.writeUInt32BE(data.length); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0)
	return Buffer.concat([length, body, checksum])
}
function png(pixels) {
	const header = Buffer.alloc(13)
	header.writeUInt32BE(2, 0); header.writeUInt32BE(2, 4); header[8] = 8; header[9] = 6
	return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk("IHDR", header),
		chunk("IDAT", deflateSync(Buffer.from([0,...pixels.slice(0,8),0,...pixels.slice(8)]))), chunk("IEND", Buffer.alloc(0))])
}

it("preserves RGBA differences, strict thresholds and exact diff pixels", () => {
	mkdirSync(resolve(repositoryRoot, ".tmp/visual"), { recursive: true })
	const root = mkdtempSync(resolve(repositoryRoot, ".tmp/visual/pixels-"))
	try {
		const reference = resolve(root, "reference.png"), actual = resolve(root, "actual.png"), diff = resolve(root, "diff.png")
		writeFileSync(reference, png([0,0,0,0, 10,20,30,40, 200,100,50,255, 20,40,80,255]))
		writeFileSync(actual, png([2,0,0,0, 10,23,30,40, 200,100,54,255, 20,40,80,250]))
		const run = (threshold, maximum) => spawnSync(process.execPath, ["tools/visual_parity/compare.mjs",
			`--reference=${reference}`, `--actual=${actual}`, `--diff=${diff}`,
			`--channel-threshold=${threshold}`, `--max-difference=${maximum}`], { cwd: repositoryRoot, encoding: "utf8" })
		const result = run(2, 75)
		expect(result.status).toBe(0)
		expect(JSON.parse(result.stdout)).toMatchObject({ pixels: 4, differentPixels: 3, differencePercent: 75, meanChannelDelta: 0.875, passed: true })
		const encoded = readFileSync(diff), compressed = []
		for (let offset = 8; offset < encoded.length;) {
			const length = encoded.readUInt32BE(offset)
			if (encoded.toString("ascii", offset + 4, offset + 8) === "IDAT") compressed.push(encoded.subarray(offset + 8, offset + 8 + length))
			offset += length + 12
		}
		expect([...inflateSync(Buffer.concat(compressed))]).toEqual([0,0,0,0,255,255,0,0,255, 0,255,0,0,255,255,0,0,255])
		const rejected = run(3, 25)
		expect(rejected.status).toBe(1)
		expect(JSON.parse(rejected.stdout)).toMatchObject({ differentPixels: 2, differencePercent: 50, meanChannelDelta: 0.875, passed: false })
	} finally { rmSync(root, { recursive: true, force: true }) }
})
