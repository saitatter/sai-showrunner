import { PowerShellCommand } from "ShowRunner-plugin-os-shared"
import { useDataInputStore } from "ShowRunner-ui-core"
import PowerShellCommandInput from "./components/PowerShellCommandInput.vue"

export function initPlugin() {
	const dataStore = useDataInputStore()

	dataStore.registerInputComponent(PowerShellCommand, PowerShellCommandInput)
}
