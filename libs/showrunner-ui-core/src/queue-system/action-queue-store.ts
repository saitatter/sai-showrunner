import { defineStore } from "pinia"
import { useIpcCaller, handleIpcMessage } from "../main"
import { AutomationData } from "ShowRunner-schema"
import { nanoid } from "nanoid/non-secure"
import { MaybeRefOrGetter, computed, ref, toValue, inject, ComputedRef, nextTick } from "vue"

export interface TestSequenceData {
	running: boolean
	activeIds: Record<string, number> //Maps active ids to their start time
	nodeResults: Record<string, any> //Maps node ids to their last execution result
	nodeErrors: Record<string, string> //Maps node ids to their error message
	nodeDurations: Record<string, number> //Maps node ids to their last execution duration in ms
	executionPath: string[]
}

export const useActionQueueStore = defineStore("actionQueues", () => {
	const runTestSequence = useIpcCaller<(id: string, automation: AutomationData) => void>(
		"actionQueue",
		"runTestSequence"
	)
	const stopTestSequence = useIpcCaller<(id: string) => void>("actionQueue", "stopTestSequence")

	const activeTestSequences = ref<Record<string, TestSequenceData>>({})

	async function initialize() {
		handleIpcMessage("actionQueue", "markTestSequenceStart", (event, sequenceId: string) => {
			activeTestSequences.value[sequenceId] = {
				running: true,
				activeIds: {},
				nodeResults: {},
				nodeErrors: {},
				nodeDurations: {},
				executionPath: [],
			}
		})

		handleIpcMessage("actionQueue", "markTestSequenceEnd", (event, sequenceId: string) => {
			const testRun = activeTestSequences.value[sequenceId]
			if (!testRun) return
			testRun.running = false
			testRun.activeIds = {}
		})

		handleIpcMessage("actionQueue", "markTestActionStart", (event, sequenceId: string, id: string) => {
			const testRun = activeTestSequences.value[sequenceId]
			if (!testRun) return //TODO: Handle out of order??
			testRun.activeIds[id] = Date.now()
			delete testRun.nodeErrors[id]
			if (testRun.executionPath[testRun.executionPath.length - 1] !== id) {
				testRun.executionPath.push(id)
			}
		})

		handleIpcMessage("actionQueue", "markTestActionEnd", (event, sequenceId: string, id: string) => {
			const testRun = activeTestSequences.value[sequenceId]
			if (!testRun) return
			const time = Date.now()
			const startTime = testRun.activeIds[id]
			if (startTime == null) return

			const diff = time - startTime
			testRun.nodeDurations[id] = diff
			const delay = 300 - diff

			//Hold for at least 300ms so the border can show up

			if (delay > 0) {
				setTimeout(() => {
					delete testRun.activeIds[id]
				}, delay)
			} else {
				delete testRun.activeIds[id]
			}
		})

		handleIpcMessage("actionQueue", "markTestActionResult", (event, sequenceId: string, id: string, result: any) => {
			const testRun = activeTestSequences.value[sequenceId]
			if (!testRun) return
			testRun.nodeResults[id] = result
		})

		handleIpcMessage("actionQueue", "markTestActionError", (event, sequenceId: string, id: string, error: string) => {
			const testRun = activeTestSequences.value[sequenceId]
			if (!testRun) return
			testRun.nodeErrors[id] = error
		})
	}

	async function testSequence(automation: AutomationData) {
		const id = nanoid()

		//TODO: Transform sequence for ipc??
		await runTestSequence(id, automation)

		return id
	}

	async function stopTest(id: string) {
		stopTestSequence(id)
	}

	return { initialize, testSequence, stopTest, activeTestSequences: computed(() => activeTestSequences.value) }
})

export function useActiveTestSequence(sequenceId: MaybeRefOrGetter<string>) {
	const actionQueueStore = useActionQueueStore()

	return computed<TestSequenceData | undefined>(() => {
		return actionQueueStore.activeTestSequences[toValue(sequenceId)]
	})
}

export function useParentTestSequence() {
	return inject<ComputedRef<TestSequenceData | undefined>>(
		"activeTestSequence",
		computed(() => undefined)
	)
}

export function useActionTestTime(actionId: MaybeRefOrGetter<string>) {
	const testSeq = useParentTestSequence()

	return computed(() => testSeq.value?.activeIds?.[toValue(actionId)])
}

export function useActionTestResult(actionId: MaybeRefOrGetter<string>) {
	const testSeq = useParentTestSequence()
	return computed(() => testSeq.value?.nodeResults?.[toValue(actionId)])
}

export function useActionTestError(actionId: MaybeRefOrGetter<string>) {
	const testSeq = useParentTestSequence()
	return computed(() => testSeq.value?.nodeErrors?.[toValue(actionId)])
}
