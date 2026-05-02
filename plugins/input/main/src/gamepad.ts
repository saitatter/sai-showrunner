import { Resource, ResourceRegistry, ResourceStorage, definePluginResource, onLoad } from "ShowRunner-core"
import { GamepadConfig } from "ShowRunner-plugin-input-shared"

export class GamepadResource extends Resource<GamepadConfig> {
	static storage = new ResourceStorage<GamepadResource>("Gamepad")
}

export function setupGamepad() {
	definePluginResource(GamepadResource)
}
