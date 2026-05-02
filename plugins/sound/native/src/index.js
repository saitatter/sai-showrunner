const EventEmitter = require("events")

let NativeAudioDeviceInterface, NativeOsTTSInterface

try {
	const bindings = require("bindings")
	const native = bindings({
		bindings: "castmate-plugin-sound-native",
	})
	NativeAudioDeviceInterface = native.NativeAudioDeviceInterface
	NativeOsTTSInterface = native.OsTTSInterface
} catch (e) {
	console.warn("[sound plugin] Native bindings not available:", e.message)
}

class AudioDeviceInterface extends EventEmitter {
	constructor() {
		super()
		if (!NativeAudioDeviceInterface) {
			console.warn("[sound plugin] AudioDeviceInterface unavailable — native module not built")
			return
		}
		const boundEmit = this.emit.bind(this)
		this._native = new NativeAudioDeviceInterface(boundEmit)
	}

	getDevices() {
		return this._native?.getDevices() ?? []
	}

	getDefaultOutput(type) {
		return this._native?.getDefaultOutput(type)
	}

	getDefaultInput(type) {
		return this._native?.getDefaultInput(type)
	}
}

const OsTTSInterface = NativeOsTTSInterface ?? class OsTTSInterfaceStub {
	getVoices() { return [] }
	speak() { return Promise.resolve() }
}

module.exports = { AudioDeviceInterface, OsTTSInterface }
