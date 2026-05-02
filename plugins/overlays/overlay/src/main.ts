import { definePluginOverlays } from "ShowRunner-overlay-core"

import LabelVue from "./widgets/Label.vue"
import EmoteBouncer from "./widgets/EmoteBouncer.vue"
import Alert from "./widgets/Alert.vue"
import Bar from "./widgets/Bar.vue"
import LeaderBoard from "./widgets/LeaderBoard.vue"
import ChatFeed from "./widgets/ChatFeed.vue"
import ShaderLayer from "./widgets/ShaderLayer.vue"

export default definePluginOverlays({
	id: "overlays",
	widgets: [LabelVue, EmoteBouncer, Alert, Bar, LeaderBoard, ChatFeed, ShaderLayer],
})
