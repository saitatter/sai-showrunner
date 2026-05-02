import { handleIpcMessage, ipcInvoke, useIpcCaller } from "ShowRunner-ui-core"
import { defineStore } from "pinia"
import { ref } from "vue"

type ExtendHTMLAudioElement = HTMLAudioElement & { setSinkId(sinkId: string): void }

interface PlayingSound {
	audioElem: ExtendHTMLAudioElement
}

export const useSoundPlayerStore = defineStore("soundPlayer", () => {
	const soundFinishedInRenderer = useIpcCaller<(id: string) => void>("sound", "soundFinishedInRenderer")

	const playingSounds = ref<Record<string, PlayingSound>>({})

	function initialize() {
		handleIpcMessage("sound", "abortSoundInRenderer", (event, id: string) => {
			const playing = playingSounds.value[id]
			if (playing) {
				playing.audioElem.pause()
				//delete playingSounds.value[id]
			}
		})

		handleIpcMessage(
			"sound",
			"playSoundInRenderer",
			(event, id: string, file: string, startSec: number, endSec: number, volume: number, sinkId: string) => {
				const audioElem: ExtendHTMLAudioElement = new Audio(`file://${file}`) as ExtendHTMLAudioElement
				audioElem.volume = volume / 100
				audioElem.setSinkId(sinkId)
				audioElem.currentTime = startSec

				audioElem.addEventListener(
					"canplaythrough",
					(event) => {
						audioElem.play()
					},
					{ once: true }
				)

				audioElem.addEventListener("timeupdate", () => {
					if (audioElem.currentTime >= endSec) audioElem.pause()
				})

				const finishSound = () => {
					soundFinishedInRenderer(id)
					delete playingSounds.value[id]
				}

				audioElem.addEventListener("pause", finishSound, { once: true })

				//audioElem.addEventListener("ended", finishSound, { once: true })

				playingSounds.value[id] = { audioElem }
			}
		)
	}

	return { initialize }
})
