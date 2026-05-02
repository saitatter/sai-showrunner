import "./css/icons.css"

import { AccountSettingList, useResourceStore } from "ShowRunner-ui-core"

export function initPlugin() {
	//Init Renderer Module

	const resourceStore = useResourceStore()

	resourceStore.registerSettingComponent("BlueSkyAccount", AccountSettingList)
}
