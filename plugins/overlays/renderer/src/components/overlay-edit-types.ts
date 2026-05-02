import { OverlayWidgetComponent } from "ShowRunner-overlay-core"
import { OverlayWidgetConfig } from "ShowRunner-plugin-overlays-shared"
import { RemoteTemplateResolutionContext, resolveRemoteTemplateSchema } from "ShowRunner-schema"
import { PanState } from "ShowRunner-ui-core"
import { ComputedRef, MaybeRefOrGetter, Ref, computed, ref, toValue } from "vue"

export interface OverlayEditView {
	panState: PanState
}

export interface OverlayEditorView {
	editView: OverlayEditView
	obsId: string | undefined
}
