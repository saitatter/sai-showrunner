import { defineStore } from "pinia"
import { useIpcCaller, handleIpcMessage } from "../main"
import { AutomationData } from "showrunner-schema"
import { nanoid } from "nanoid/non-secure"
import { MaybeRefOrGetter, computed, ref, toValue, inject, ComputedRef, nextTick } from "vue"

export interface TestExecutionData {
	running: boolean
	activeIds: Record<string, number> //Maps active ids to their start time
	nodeResults: Record<string, any> //Maps node ids to their last execution result
	nodeErrors: Record<string, string> //Maps node ids to their error message
	nodeDurations: Record<string, number> //Maps node ids to their last execution duration in ms
	executionPath: string[]
}

export const useActionQueueStore = defineStore("actionQueues", () => {
	const runTestExecution = useIpcCaller<(id: string, automation: AutomationData) => void>(
		"actionQueue",
		"runTestExecution"
	)
	const stopTestExecution = useIpcCaller<(id: string) => void>("actionQueue", "stopTestExecution")

	const activeTestExecutions = ref<Record<string, TestExecutionData>>({})

	async function initialize() {
		handleIpcMessage("actionQueue", "markTestExecutionStart", (event, executionId: string) => {
			activeTestExecutions.value[executionId] = {
				running: true,
				activeIds: {},
				nodeResults: {},
				nodeErrors: {},
				nodeDurations: {},
				executionPath: [],
			}
		})

		handleIpcMessage("actionQueue", "markTestExecutionEnd", (event, executionId: string) => {
			const testRun = activeTestExecutions.value[executionId]
			if (!testRun) return
			testRun.running = false
			testRun.activeIds = {}
		})

		handleIpcMessage("actionQueue", "markTestActionStart", (event, executionId: string, id: string) => {
			const testRun = activeTestExecutions.value[executionId]
			if (!testRun) return //TODO: Handle out of order??
			testRun.activeIds[id] = Date.now()
			delete testRun.nodeErrors[id]
			if (testRun.executionPath[testRun.executionPath.length - 1] !== id) {
				testRun.executionPath.push(id)
			}
		})

		handleIpcMessage("actionQueue", "markTestActionEnd", (event, executionId: string, id: string) => {
			const testRun = activeTestExecutions.value[executionId]
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

		handleIpcMessage("actionQueue", "markTestActionResult", (event, executionId: string, id: string, result: any) => {
			const testRun = activeTestExecutions.value[executionId]
			if (!testRun) return
			testRun.nodeResults[id] = result
		})

		handleIpcMessage("actionQueue", "markTestActionError", (event, executionId: string, id: string, error: string) => {
			const testRun = activeTestExecutions.value[executionId]
			if (!testRun) return
			testRun.nodeErrors[id] = error
		})
	}

	async function testExecution(automation: AutomationData) {
		const id = nanoid()

		await runTestExecution(id, automation)

		return id
	}

	async function stopExecution(id: string) {
		stopTestExecution(id)
	}

	return { initialize, testExecution, stopExecution, activeTestExecutions: computed(() => activeTestExecutions.value) }
})

export function useActiveTestExecution(executionId: MaybeRefOrGetter<string>) {
	const actionQueueStore = useActionQueueStore()

	return computed<TestExecutionData | undefined>(() => {
		return actionQueueStore.activeTestExecutions[toValue(executionId)]
	})
}

export function useParentTestExecution() {
	return inject<ComputedRef<TestExecutionData | undefined>>(
		"activeTestExecution",
		computed(() => undefined)
	)
}

export function useActionTestTime(actionId: MaybeRefOrGetter<string>) {
	const testExecution = useParentTestExecution()

	return computed(() => testExecution.value?.activeIds?.[toValue(actionId)])
}

export function useActionTestResult(actionId: MaybeRefOrGetter<string>) {
	const testExecution = useParentTestExecution()
	return computed(() => testExecution.value?.nodeResults?.[toValue(actionId)])
}

export function useActionTestError(actionId: MaybeRefOrGetter<string>) {
	const testExecution = useParentTestExecution()
	return computed(() => testExecution.value?.nodeErrors?.[toValue(actionId)])
}
