import { Resource, ResourceRegistry, ResourceStorage, definePluginResource, onLoad } from "showrunner-core"
import { GamepadConfig } from "showrunner-plugin-input-shared"

export class GamepadResource extends Resource<GamepadConfig> {
	static storage = new ResourceStorage<GamepadResource>("Gamepad")
}

export function setupGamepad() {
	definePluginResource(GamepadResource)
}
