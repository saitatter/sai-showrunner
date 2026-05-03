import { SchemaBase, registerType } from "showrunner-schema"

export type PowerShellCommand = string

export type PowerShellCommandFactory = {
	factoryCreate(): PowerShellCommand
}
export const PowerShellCommand: PowerShellCommandFactory = {
	factoryCreate() {
		return ""
	},
}

export interface SchemaPowerShellCommand extends SchemaBase<PowerShellCommand> {
	type: PowerShellCommandFactory
	template?: boolean
}

declare module "showrunner-schema" {
	interface SchemaTypeMap {
		PowerShellCommand: [SchemaPowerShellCommand, PowerShellCommand]
	}
}

registerType("PowerShellCommand", {
	constructor: PowerShellCommand,
})
