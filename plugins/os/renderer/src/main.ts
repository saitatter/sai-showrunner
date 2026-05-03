import { PowerShellCommand } from "showrunner-plugin-os-shared"
import { useDataInputStore } from "showrunner-ui-core"
import PowerShellCommandInput from "./components/PowerShellCommandInput.vue"

export function initPlugin() {
	const dataStore = useDataInputStore()

	dataStore.registerInputComponent(PowerShellCommand, PowerShellCommandInput)
}
