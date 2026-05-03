import { OverlayWidgetComponent } from "showrunner-overlay-core"
import { OverlayWidgetConfig } from "showrunner-plugin-overlays-shared"
import { RemoteTemplateResolutionContext, resolveRemoteTemplateSchema } from "showrunner-schema"
import { PanState } from "showrunner-ui-core"
import { ComputedRef, MaybeRefOrGetter, Ref, computed, ref, toValue } from "vue"

export interface OverlayEditView {
	panState: PanState
}

export interface OverlayEditorView {
	editView: OverlayEditView
	obsId: string | undefined
}
