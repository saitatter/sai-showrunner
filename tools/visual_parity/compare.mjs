import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { deflateSync, inflateSync } from "node:zlib"

const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

function usage() {
	console.error(
		"Usage: node tools/visual_parity/compare.mjs " +
		"--reference=<path> --actual=<path> [--diff=<path>] " +
		"[--report=<path>] [--channel-threshold=<0..255>] " +
		"[--max-difference=<percent>]",
	)
}

function argumentsFrom(argv) {
	const options = new Map()
	for (const argument of argv) {
		if (!argument.startsWith("--")) continue
		const separator = argument.indexOf("=")
		if (separator < 0) {
			options.set(argument.slice(2), "true")
			continue
		}
		options.set(argument.slice(2, separator), argument.slice(separator + 1))
	}
	return options
}

function paeth(a, b, c) {
	const estimate = a + b - c
	const distanceA = Math.abs(estimate - a)
	const distanceB = Math.abs(estimate - b)
	const distanceC = Math.abs(estimate - c)
	if (distanceA <= distanceB && distanceA <= distanceC) return a
	if (distanceB <= distanceC) return b
	return c
}

function unfilterScanlines(data, height, bytesPerPixel, rowLength) {
	const result = Buffer.alloc(height * rowLength)
	let inputOffset = 0
	for (let row = 0; row < height; row += 1) {
		const filter = data[inputOffset++]
		const rowOffset = row * rowLength
		const previousOffset = rowOffset - rowLength
		for (let column = 0; column < rowLength; column += 1) {
			const raw = data[inputOffset++]
			const left = column >= bytesPerPixel ? result[rowOffset + column - bytesPerPixel] : 0
			const above = row > 0 ? result[previousOffset + column] : 0
			const upperLeft = row > 0 && column >= bytesPerPixel
				? result[previousOffset + column - bytesPerPixel]
				: 0
			let value
			switch (filter) {
				case 0:
					value = raw
					break
				case 1:
					value = raw + left
					break
				case 2:
					value = raw + above
					break
				case 3:
					value = raw + Math.floor((left + above) / 2)
					break
				case 4:
					value = raw + paeth(left, above, upperLeft)
					break
				default:
					throw new Error(`Unsupported PNG filter type: ${filter}`)
			}
			result[rowOffset + column] = value & 0xff
		}
	}
	if (inputOffset !== data.length) throw new Error("PNG scanline data has trailing bytes")
	return result
}

function decodePng(buffer) {
	if (!buffer.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
		throw new Error("File is not a PNG")
	}

	let offset = PNG_SIGNATURE.length
	let header
	const compressed = []
	let palette
	let transparency
	while (offset < buffer.length) {
		const length = buffer.readUInt32BE(offset)
		const type = buffer.toString("ascii", offset + 4, offset + 8)
		const data = buffer.subarray(offset + 8, offset + 8 + length)
		offset += length + 12
		switch (type) {
			case "IHDR":
				header = {
					width: data.readUInt32BE(0),
					height: data.readUInt32BE(4),
					bitDepth: data[8],
					colorType: data[9],
					compression: data[10],
					filter: data[11],
					interlace: data[12],
				}
				break
			case "PLTE":
				palette = data
				break
			case "tRNS":
				transparency = data
				break
			case "IDAT":
				compressed.push(data)
				break
			case "IEND":
				offset = buffer.length
				break
		}
	}

	if (!header) throw new Error("PNG has no IHDR chunk")
	if (header.bitDepth !== 8 || header.compression !== 0 || header.filter !== 0 || header.interlace !== 0) {
		throw new Error("Only non-interlaced 8-bit PNGs are supported")
	}
	const channelsByColorType = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }
	const channels = channelsByColorType[header.colorType]
	if (!channels) throw new Error(`Unsupported PNG color type: ${header.colorType}`)
	if (header.colorType === 3 && (!palette || palette.length % 3 !== 0)) {
		throw new Error("Indexed PNG has no valid palette")
	}

	const rowLength = header.width * channels
	const scanlines = unfilterScanlines(
		inflateSync(Buffer.concat(compressed)),
		header.height,
		channels,
		rowLength,
	)
	const rgba = Buffer.alloc(header.width * header.height * 4)
	for (let row = 0; row < header.height; row += 1) {
		for (let column = 0; column < header.width; column += 1) {
			const source = row * rowLength + column * channels
			const target = (row * header.width + column) * 4
			switch (header.colorType) {
				case 0: {
					const value = scanlines[source]
					rgba[target] = value
					rgba[target + 1] = value
					rgba[target + 2] = value
					rgba[target + 3] = transparency?.[0] === value ? 0 : 255
					break
				}
				case 2:
					rgba[target] = scanlines[source]
					rgba[target + 1] = scanlines[source + 1]
					rgba[target + 2] = scanlines[source + 2]
					rgba[target + 3] = 255
					break
				case 3: {
					const paletteIndex = scanlines[source]
					const paletteOffset = paletteIndex * 3
					if (paletteOffset + 2 >= palette.length) throw new Error("PNG palette index is out of range")
					rgba[target] = palette[paletteOffset]
					rgba[target + 1] = palette[paletteOffset + 1]
					rgba[target + 2] = palette[paletteOffset + 2]
					rgba[target + 3] = transparency?.[paletteIndex] ?? 255
					break
				}
				case 4:
					rgba[target] = scanlines[source]
					rgba[target + 1] = scanlines[source]
					rgba[target + 2] = scanlines[source]
					rgba[target + 3] = scanlines[source + 1]
					break
				case 6:
					rgba[target] = scanlines[source]
					rgba[target + 1] = scanlines[source + 1]
					rgba[target + 2] = scanlines[source + 2]
					rgba[target + 3] = scanlines[source + 3]
					break
			}
		}
	}
	return { width: header.width, height: header.height, rgba }
}

function crc32(buffer) {
	let crc = 0xffffffff
	for (const byte of buffer) {
		crc ^= byte
		for (let bit = 0; bit < 8; bit += 1) {
			crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0)
		}
	}
	return (crc ^ 0xffffffff) >>> 0
}

function pngChunk(type, data) {
	const typeBuffer = Buffer.from(type, "ascii")
	const result = Buffer.alloc(12 + data.length)
	result.writeUInt32BE(data.length, 0)
	typeBuffer.copy(result, 4)
	data.copy(result, 8)
	result.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 8 + data.length)
	return result
}

function encodePng(image) {
	const rowLength = image.width * 4
	const scanlines = Buffer.alloc(image.height * (rowLength + 1))
	for (let row = 0; row < image.height; row += 1) {
		const target = row * (rowLength + 1)
		scanlines[target] = 0
		image.rgba.copy(scanlines, target + 1, row * rowLength, (row + 1) * rowLength)
	}
	const header = Buffer.alloc(13)
	header.writeUInt32BE(image.width, 0)
	header.writeUInt32BE(image.height, 4)
	header[8] = 8
	header[9] = 6
	return Buffer.concat([
		PNG_SIGNATURE,
		pngChunk("IHDR", header),
		pngChunk("IDAT", deflateSync(scanlines)),
		pngChunk("IEND", Buffer.alloc(0)),
	])
}

function compare(reference, actual, channelThreshold) {
	if (reference.width !== actual.width || reference.height !== actual.height) {
		throw new Error(
			`Image dimensions differ: reference=${reference.width}x${reference.height}, ` +
			`actual=${actual.width}x${actual.height}`,
		)
	}

	const pixels = reference.width * reference.height
	const diff = Buffer.alloc(reference.rgba.length)
	let differentPixels = 0
	let totalChannelDelta = 0
	for (let offset = 0; offset < reference.rgba.length; offset += 4) {
		const channelDelta = [0, 1, 2, 3].map((channel) =>
			Math.abs(reference.rgba[offset + channel] - actual.rgba[offset + channel]),
		)
		const maxDelta = Math.max(...channelDelta)
		totalChannelDelta += channelDelta.reduce((sum, value) => sum + value, 0)
		if (maxDelta > channelThreshold) {
			differentPixels += 1
			diff[offset] = 255
			diff[offset + 3] = 255
		} else {
			const luminance = Math.round(
				(actual.rgba[offset] * 0.299 + actual.rgba[offset + 1] * 0.587 + actual.rgba[offset + 2] * 0.114) * 0.25,
			)
			diff[offset] = luminance
			diff[offset + 1] = luminance
			diff[offset + 2] = luminance
			diff[offset + 3] = 255
		}
	}
	return {
		width: reference.width,
		height: reference.height,
		pixels,
		differentPixels,
		differencePercent: (differentPixels / pixels) * 100,
		meanChannelDelta: totalChannelDelta / (pixels * 4),
		diff: { width: reference.width, height: reference.height, rgba: diff },
	}
}

const options = argumentsFrom(process.argv.slice(2))
const referencePath = options.get("reference")
const actualPath = options.get("actual")
if (!referencePath || !actualPath) {
	usage()
	process.exit(2)
}

const channelThreshold = Number(options.get("channel-threshold") ?? 0)
const maxDifference = Number(options.get("max-difference") ?? 0)
if (!Number.isFinite(channelThreshold) || channelThreshold < 0 || channelThreshold > 255) {
	throw new Error("--channel-threshold must be between 0 and 255")
}
if (!Number.isFinite(maxDifference) || maxDifference < 0 || maxDifference > 100) {
	throw new Error("--max-difference must be between 0 and 100")
}

const result = compare(
	decodePng(await readFile(referencePath)),
	decodePng(await readFile(actualPath)),
	channelThreshold,
)
if (options.has("diff")) {
	const diffPath = options.get("diff")
	await mkdir(dirname(diffPath), { recursive: true })
	await writeFile(diffPath, encodePng(result.diff))
}

const report = {
	reference: referencePath,
	actual: actualPath,
	width: result.width,
	height: result.height,
	pixels: result.pixels,
	differentPixels: result.differentPixels,
	differencePercent: Number(result.differencePercent.toFixed(6)),
	meanChannelDelta: Number(result.meanChannelDelta.toFixed(6)),
	channelThreshold,
	maxDifference,
	passed: result.differencePercent <= maxDifference,
}
if (options.has("report")) {
	const reportPath = options.get("report")
	await mkdir(dirname(reportPath), { recursive: true })
	await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`)
}
console.log(JSON.stringify(report))
if (!report.passed) process.exitCode = 1
