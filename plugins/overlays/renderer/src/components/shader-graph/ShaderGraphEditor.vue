<template>
	<div class="shader-graph" :style="shaderGraphSkinStyle">
		<header class="shader-graph__toolbar">
			<h3><i class="mdi mdi-magic-staff" /> Shader Graph</h3>
			<div class="shader-graph__toolbar-actions">
				<button type="button" class="shader-graph__tool-button" @click="zoomOut" v-tooltip="'Zoom out'">
					<i class="mdi mdi-magnify-minus-outline" />
				</button>
				<span class="shader-graph__zoom-label">{{ zoomLabel }}</span>
				<button type="button" class="shader-graph__tool-button" @click="zoomIn" v-tooltip="'Zoom in'">
					<i class="mdi mdi-magnify-plus-outline" />
				</button>
				<button type="button" class="shader-graph__tool-button" @click="fitGraph" v-tooltip="'Fit graph'">
					<i class="mdi mdi-fit-to-screen-outline" />
				</button>
				<button type="button" class="shader-graph__tool-button" :disabled="!selectedNode" @click="fitSelection" v-tooltip="'Fit selected node'">
					<i class="mdi mdi-selection-search" />
				</button>
				<button type="button" class="shader-graph__tool-button" :disabled="!canUndo" @click="undoGraph" v-tooltip="'Undo'">
					<i class="mdi mdi-undo" />
				</button>
				<button type="button" class="shader-graph__tool-button" :disabled="!canRedo" @click="redoGraph" v-tooltip="'Redo'">
					<i class="mdi mdi-redo" />
				</button>
				<button type="button" class="shader-graph__tool-button" @click="resetGraph" v-tooltip="'Reset graph'">
					<i class="mdi mdi-restore" />
				</button>
				<button
					type="button"
					class="shader-graph__tool-button"
					:class="{ active: showGrid }"
					@click="showGrid = !showGrid"
					v-tooltip="'Toggle grid'"
				>
					<i class="mdi mdi-grid" />
				</button>
				<button
					type="button"
					class="shader-graph__tool-button"
					:class="{ active: snapToGrid }"
					@click="snapToGrid = !snapToGrid"
					v-tooltip="'Snap to grid'"
				>
					<i class="mdi mdi-grid-large" />
				</button>
				<button type="button" class="shader-graph__tool-button" @click="layoutGraphByCategory" v-tooltip="'Auto layout'">
					<i class="mdi mdi-sitemap-outline" />
				</button>
				<button
					type="button"
					class="shader-graph__tool-button"
					:class="{ active: showMinimap }"
					@click="showMinimap = !showMinimap"
					v-tooltip="'Toggle minimap'"
				>
					<i class="mdi mdi-selection-ellipse-arrow-inside" />
				</button>
				<span class="shader-graph__toolbar-divider" />
				<label class="shader-graph__toolbar-control" v-tooltip="'Preview quality'">
					<i class="mdi mdi-speedometer" />
					<select v-model="shaderQualityPreset" @change="applyQualityPreset">
						<option value="draft">Draft</option>
						<option value="balanced">Balanced</option>
						<option value="high">High</option>
					</select>
				</label>
				<label class="shader-graph__toolbar-control" v-tooltip="'Preview FPS cap'">
					<i class="mdi mdi-timer-outline" />
					<input v-model.number="previewFpsLimit" type="number" min="5" max="60" step="5" />
				</label>
				<label class="shader-graph__toolbar-control" v-tooltip="'Starter graph'">
					<i class="mdi mdi-creation" />
					<select v-model="selectedStarterId">
						<option value="">Starter...</option>
						<option v-for="starter in SHADER_GRAPH_STARTERS" :key="starter.id" :value="starter.id">
							{{ starter.name }}
						</option>
					</select>
				</label>
				<button type="button" :disabled="!selectedStarterId" @click="loadSelectedStarter" v-tooltip="'Load starter graph'">
					<i class="mdi mdi-file-replace-outline" />
				</button>
				<label class="shader-graph__toolbar-control shader-graph__toolbar-control--preset" v-tooltip="'Local graph preset'">
					<i class="mdi mdi-folder-star-outline" />
					<select v-model="selectedGraphPresetName">
						<option value="">Graph preset...</option>
						<option v-for="name in graphPresetNames" :key="name" :value="name">
							{{ name }}
						</option>
					</select>
					<input
						v-model="graphPresetName"
						type="text"
						placeholder="Name"
						@keydown.enter.prevent="saveGraphPreset"
					/>
				</label>
				<button type="button" :disabled="!canSaveGraphPreset" @click="saveGraphPreset" v-tooltip="'Save graph preset'">
					<i class="mdi mdi-content-save-outline" />
				</button>
				<button type="button" :disabled="!selectedGraphPresetName" @click="loadSelectedGraphPreset" v-tooltip="'Load graph preset'">
					<i class="mdi mdi-folder-open-outline" />
				</button>
				<button type="button" :disabled="!selectedGraphPresetName" @click="deleteSelectedGraphPreset" v-tooltip="'Delete graph preset'">
					<i class="mdi mdi-delete-outline" />
				</button>
				<span class="shader-graph__toolbar-divider" />
				<button type="button" class="shader-graph__tool-button" @click="sidePanelTab = 'code'" :class="{ active: sidePanelTab === 'code' }" v-tooltip="'Show GLSL'">
					<i class="mdi mdi-code-tags" />
				</button>
				<button type="button" class="shader-graph__tool-button shader-graph__tool-button--run" @click="compileAndApply" v-tooltip="'Compile & Apply'">
					<i class="mdi mdi-play" />
				</button>
				<button type="button" class="shader-graph__tool-button" @click="stopPreview" v-tooltip="'Stop preview'">
					<i class="mdi mdi-stop" />
				</button>
				<button type="button" class="shader-graph__close" @click="emit('close')">
					<i class="mdi mdi-close" /> Close
				</button>
			</div>
		</header>

		<div class="shader-graph__body">
			<aside class="shader-graph__inputs">
				<header>
					<strong>Inputs</strong>
					<span>Uniforms and shader sources</span>
				</header>
				<div class="shader-graph__input-list">
					<button
						v-for="def in inputPaletteDefs"
						:key="def.id"
						type="button"
						@click="addNodeFromPalette(def.id)"
					>
						<i :class="def.icon" />
						<span>
							<strong>{{ def.name }}</strong>
							<small>{{ def.outputs[0]?.type ?? "input" }}</small>
						</span>
					</button>
				</div>
			</aside>

			<section
				ref="canvasRef"
				class="shader-graph__canvas"
				:class="{ 'shader-graph__canvas--grid': showGrid }"
				@pointerdown="onCanvasPointerDown"
				@contextmenu.prevent="openPalette"
				@wheel.ctrl.prevent="onZoom"
			>
				<div
					class="shader-graph__surface"
					:style="{
						transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
						width: `${surfaceSize.width}px`,
						height: `${surfaceSize.height}px`,
					}"
				>
					<!-- Wires SVG -->
					<svg class="shader-graph__wires" :viewBox="`0 0 ${surfaceSize.width} ${surfaceSize.height}`">
						<path
							v-for="wire in wirePaths"
							:key="wire.id"
							class="shader-graph__wire"
							:class="{ selected: selectedWireId === wire.id }"
							:d="wire.path"
							:stroke="wire.color"
							vector-effect="non-scaling-stroke"
							@click.stop="selectedWireId = wire.id"
						/>
						<path
							v-if="dragWire"
							class="shader-graph__wire shader-graph__wire--dragging"
							:class="{ 'shader-graph__wire--invalid': !dragWire.valid }"
							:d="dragWire.path"
							:stroke="dragWire.color"
							vector-effect="non-scaling-stroke"
						/>
					</svg>

					<!-- Nodes -->
					<div
						v-for="node in graphNodes"
						:key="node.id"
						class="shader-graph__node"
						:class="{ selected: selectedNodeId === node.id, output: node.defId === 'fragment_output' }"
						:style="{ transform: `translate(${node.x}px, ${node.y}px)` }"
						@pointerdown.stop="startNodeDrag($event, node)"
						@click.stop="selectedNodeId = node.id"
						@pointerup.stop="selectNode(node.id)"
					>
						<header class="shader-graph__node-header" :style="{ background: categoryColor(node.category) }">
							<i :class="node.icon" />
							<span>{{ nodeTitle(node) }}</span>
						</header>

						<!-- Preview canvas -->
						<canvas
							v-if="shouldShowNodePreview(node)"
							:ref="(el) => setPreviewRef(node.id, el as HTMLCanvasElement)"
							class="shader-graph__node-preview"
							width="160"
							height="80"
						/>

						<!-- Input ports -->
						<div class="shader-graph__ports">
							<div class="shader-graph__port-column shader-graph__port-column--in">
								<div
									v-for="port in node.inputs"
									:key="port.key"
									class="shader-graph__port"
								>
									<span
										class="shader-graph__port-dot"
										:data-shader-port-node-id="node.id"
										:data-shader-port-key="port.key"
										:data-shader-port-kind="'in'"
										:style="{ background: typeColor(port.type) }"
										@pointerdown.stop="startWireDrag($event, node.id, port.key, 'in', port.type)"
									/>
									<span class="shader-graph__port-name">{{ port.label }}</span>
									<span class="shader-graph__port-type">{{ port.type }}</span>
								</div>
							</div>
							<div class="shader-graph__port-column shader-graph__port-column--out">
								<div
									v-for="port in node.outputs"
									:key="port.key"
									class="shader-graph__port shader-graph__port--out"
								>
									<span class="shader-graph__port-type">{{ port.type }}</span>
									<span class="shader-graph__port-name">{{ port.label }}</span>
									<span
										class="shader-graph__port-dot"
										:data-shader-port-node-id="node.id"
										:data-shader-port-key="port.key"
										:data-shader-port-kind="'out'"
										:style="{ background: typeColor(port.type) }"
										@pointerdown.stop="startWireDrag($event, node.id, port.key, 'out', port.type)"
									/>
								</div>
							</div>
						</div>
					</div>
				</div>

				<div v-if="showMinimap" class="shader-graph__minimap">
					<div
						v-for="node in minimapNodes"
						:key="node.id"
						class="shader-graph__minimap-node"
						:class="{ selected: selectedNodeId === node.id }"
						:style="{ left: `${node.x}%`, top: `${node.y}%`, width: `${node.width}%`, height: `${node.height}%` }"
					/>
					<div
						class="shader-graph__minimap-viewport"
						:style="{ left: `${minimapViewport.x}%`, top: `${minimapViewport.y}%`, width: `${minimapViewport.width}%`, height: `${minimapViewport.height}%` }"
					/>
				</div>

				<!-- Node palette (right-click) -->
				<div
					v-if="paletteOpen"
				>
					<collapsible-context-menu
						:x="palettePos.x"
						:y="palettePos.y"
						title="Shader Nodes"
						subtitle="Add procedural building blocks"
						width="320px"
						@close="paletteOpen = false"
					>
						<template #search>
							<label class="shader-graph__palette-search">
								<i class="mdi mdi-magnify" />
								<input
									ref="paletteInputRef"
									v-model="paletteQuery"
									type="search"
									placeholder="Search nodes..."
									@keydown.escape.prevent="paletteOpen = false"
								/>
							</label>
						</template>
						<div v-if="contextMenuQueryResults.length" class="shader-graph__menu-section">
							<div class="shader-graph__menu-section-header shader-graph__menu-section-header--static">
								<i class="mdi mdi-magnify" />
								<span>Search results</span>
								<em>{{ contextMenuQueryResults.length }}</em>
							</div>
							<div class="shader-graph__palette-list">
								<button
									v-for="def in contextMenuQueryResults"
									:key="def.id"
									type="button"
									@click="addNode(def.id)"
								>
									<i :class="def.icon" />
									{{ def.name }}
									<small>{{ def.category }}</small>
								</button>
							</div>
						</div>
						<p v-else-if="paletteQuery.trim()" class="shader-graph__empty-state">No shader nodes found.</p>
						<div
							v-for="cat in contextMenuCategories"
							v-else
							:key="cat.name"
							class="shader-graph__menu-section"
						>
							<button
								type="button"
								class="shader-graph__menu-section-header"
								:aria-expanded="isContextGroupOpen(cat.name)"
								@click="toggleContextGroup(cat.name)"
							>
								<i :class="isContextGroupOpen(cat.name) ? 'mdi mdi-chevron-down' : 'mdi mdi-chevron-right'" />
								<span>{{ cat.name }}</span>
								<em>{{ cat.defs.length }}</em>
							</button>
							<div v-if="isContextGroupOpen(cat.name)" class="shader-graph__palette-list">
								<button
									v-for="def in cat.defs"
									:key="def.id"
									type="button"
									@click="addNode(def.id)"
								>
									<i :class="def.icon" />
									{{ def.name }}
									<small>{{ def.outputs[0]?.type ?? def.inputs[0]?.type ?? "node" }}</small>
								</button>
							</div>
						</div>
					</collapsible-context-menu>
				</div>
			</section>

			<aside class="shader-graph__side-panel">
				<header class="shader-graph__tabs">
					<button type="button" :class="{ active: sidePanelTab === 'node' }" :disabled="!selectedNode" @click="sidePanelTab = 'node'">
						<i class="mdi mdi-tune" /> Node
					</button>
					<button type="button" :class="{ active: sidePanelTab === 'preview' }" @click="sidePanelTab = 'preview'">
						<i class="mdi mdi-eye-outline" /> Preview
					</button>
					<button type="button" :class="{ active: sidePanelTab === 'errors' }" @click="sidePanelTab = 'errors'">
						<i class="mdi mdi-alert-circle-outline" /> Errors {{ compileErrors.length }}
					</button>
					<button type="button" :class="{ active: sidePanelTab === 'code' }" @click="sidePanelTab = 'code'">
						<i class="mdi mdi-code-tags" /> GLSL
					</button>
				</header>

				<section v-if="sidePanelTab === 'node'" class="shader-graph__node-inspector">
					<template v-if="selectedNode && selectedNodeDef">
						<header>
							<i :class="selectedNodeDef.icon" />
							<div>
								<strong>{{ selectedNodeDef.name }}</strong>
								<span>{{ selectedNodeDef.category }}</span>
							</div>
						</header>

						<label v-if="isUniformParameterNode(selectedNode)" class="shader-graph__field">
							<span>Uniform Name</span>
							<input
								type="text"
								:value="getNodeInputDefault(selectedNode, 'name', 'parameter')"
								@input="setNodeInputDefault(selectedNode, 'name', ($event.target as HTMLInputElement).value)"
							/>
						</label>

						<div v-if="isUniformParameterNode(selectedNode)" class="shader-graph__field-group shader-graph__field-group--compact">
							<h4>Runtime Binding</h4>
							<label class="shader-graph__field">
								<span>Source</span>
								<select
									:value="getUniformBindingSource(selectedNode)"
									@change="setUniformBindingSource(selectedNode, ($event.target as HTMLSelectElement).value)"
								>
									<option value="none">Default value</option>
									<option value="config">Widget config path</option>
									<option value="state">Plugin state path</option>
								</select>
							</label>
							<label v-if="getUniformBindingSource(selectedNode) === 'config'" class="shader-graph__field">
								<span>Config Path</span>
								<input
									type="text"
									placeholder="intensity"
									:value="getNodeInputDefault(selectedNode, 'bindingPath', '')"
									@input="setNodeInputDefault(selectedNode, 'bindingPath', ($event.target as HTMLInputElement).value)"
								/>
							</label>
							<div v-if="getUniformBindingSource(selectedNode) === 'state'" class="shader-graph__field-row">
								<label class="shader-graph__field">
									<span>Plugin</span>
									<input
										type="text"
										placeholder="audio"
										:value="getNodeInputDefault(selectedNode, 'bindingPlugin', '')"
										@input="setNodeInputDefault(selectedNode, 'bindingPlugin', ($event.target as HTMLInputElement).value)"
									/>
								</label>
								<label class="shader-graph__field">
									<span>State</span>
									<input
										type="text"
										placeholder="meter"
										:value="getNodeInputDefault(selectedNode, 'bindingState', '')"
										@input="setNodeInputDefault(selectedNode, 'bindingState', ($event.target as HTMLInputElement).value)"
									/>
								</label>
								<label class="shader-graph__field">
									<span>Path</span>
									<input
										type="text"
										placeholder="value"
										:value="getNodeInputDefault(selectedNode, 'bindingPath', '')"
										@input="setNodeInputDefault(selectedNode, 'bindingPath', ($event.target as HTMLInputElement).value)"
									/>
								</label>
							</div>
						</div>

						<label v-if="selectedNode.defId === 'float_const' || selectedNode.defId === 'uniform_float'" class="shader-graph__field">
							<span>Value</span>
							<input
								v-if="selectedNode.defId === 'uniform_float'"
								type="range"
								:min="getNodeInputDefault(selectedNode, 'min', '0')"
								:max="getNodeInputDefault(selectedNode, 'max', '1')"
								:step="getNodeInputDefault(selectedNode, 'step', '0.01')"
								:value="getNodeInputDefault(selectedNode, 'value', '1.0')"
								@input="setNodeInputDefault(selectedNode, 'value', ($event.target as HTMLInputElement).value || '0.0')"
							/>
							<input
								type="number"
								:step="selectedNode.defId === 'uniform_float' ? getNodeInputDefault(selectedNode, 'step', '0.01') : '0.01'"
								:value="getNodeInputDefault(selectedNode, 'value', '1.0')"
								@input="setNodeInputDefault(selectedNode, 'value', ($event.target as HTMLInputElement).value || '0.0')"
							/>
						</label>

						<div v-if="selectedNode.defId === 'uniform_float'" class="shader-graph__field-row">
							<label class="shader-graph__field">
								<span>Min</span>
								<input
									type="number"
									step="0.01"
									:value="getNodeInputDefault(selectedNode, 'min', '0')"
									@input="setNodeInputDefault(selectedNode, 'min', ($event.target as HTMLInputElement).value || '0')"
								/>
							</label>
							<label class="shader-graph__field">
								<span>Max</span>
								<input
									type="number"
									step="0.01"
									:value="getNodeInputDefault(selectedNode, 'max', '1')"
									@input="setNodeInputDefault(selectedNode, 'max', ($event.target as HTMLInputElement).value || '1')"
								/>
							</label>
							<label class="shader-graph__field">
								<span>Step</span>
								<input
									type="number"
									step="0.01"
									:value="getNodeInputDefault(selectedNode, 'step', '0.01')"
									@input="setNodeInputDefault(selectedNode, 'step', ($event.target as HTMLInputElement).value || '0.01')"
								/>
							</label>
						</div>

						<div v-if="selectedNode.defId === 'uniform_vec2'" class="shader-graph__field-row">
							<label class="shader-graph__field">
								<span>X</span>
								<input
									type="number"
									step="0.01"
									:value="vec2DefaultComponent(getNodeInputDefault(selectedNode, 'value', 'vec2(0.0, 0.0)'), 0)"
									@input="setVec2InputDefaultComponent(selectedNode, 'value', 0, ($event.target as HTMLInputElement).value || '0.0')"
								/>
							</label>
							<label class="shader-graph__field">
								<span>Y</span>
								<input
									type="number"
									step="0.01"
									:value="vec2DefaultComponent(getNodeInputDefault(selectedNode, 'value', 'vec2(0.0, 0.0)'), 1)"
									@input="setVec2InputDefaultComponent(selectedNode, 'value', 1, ($event.target as HTMLInputElement).value || '0.0')"
								/>
							</label>
						</div>

						<label v-if="selectedNode.defId === 'vec3_const' || selectedNode.defId === 'uniform_vec3'" class="shader-graph__field">
							<span>Color</span>
							<input
								type="color"
								:value="vec3DefaultToHex(getNodeInputDefault(selectedNode, 'value', 'vec3(1.0, 1.0, 1.0)'))"
								@input="setNodeInputDefault(selectedNode, 'value', hexToVec3(($event.target as HTMLInputElement).value))"
							/>
						</label>

						<label v-if="selectedNode.defId === 'comment_frame'" class="shader-graph__field">
							<span>Title</span>
							<input
								type="text"
								:value="getNodeInputDefault(selectedNode, 'title', 'Comment')"
								@input="setNodeInputDefault(selectedNode, 'title', ($event.target as HTMLInputElement).value)"
							/>
						</label>

						<label v-if="selectedNode.defId === 'comment_frame'" class="shader-graph__field">
							<span>Note</span>
							<textarea
								:value="getNodeInputDefault(selectedNode, 'note', '')"
								@input="setNodeInputDefault(selectedNode, 'note', ($event.target as HTMLTextAreaElement).value)"
							/>
						</label>

						<div v-if="selectedNode.defId === 'color_ramp'" class="shader-graph__field-group">
							<h4>Color Ramp</h4>
							<div class="shader-graph__ramp-preview" :style="{ background: colorRampPreview(selectedNode) }" />
							<div class="shader-graph__ramp-stop-list">
								<div
									v-for="(stop, index) in getColorRampStops(selectedNode)"
									:key="index"
									class="shader-graph__ramp-stop"
								>
									<input
										type="color"
										:value="vec3DefaultToHex(stop.color)"
										@input="setColorRampStopColor(selectedNode, index, ($event.target as HTMLInputElement).value)"
									/>
									<input
										type="range"
										min="0"
										max="1"
										step="0.01"
										:value="stop.offset"
										@input="setColorRampStopOffset(selectedNode, index, ($event.target as HTMLInputElement).value)"
									/>
									<input
										type="number"
										min="0"
										max="1"
										step="0.01"
										:value="stop.offset"
										@input="setColorRampStopOffset(selectedNode, index, ($event.target as HTMLInputElement).value)"
									/>
									<button type="button" :disabled="index === 0" @click="moveColorRampStop(selectedNode, index, -1)" v-tooltip="'Move stop left'">
										<i class="mdi mdi-arrow-up" />
									</button>
									<button type="button" :disabled="index === getColorRampStops(selectedNode).length - 1" @click="moveColorRampStop(selectedNode, index, 1)" v-tooltip="'Move stop right'">
										<i class="mdi mdi-arrow-down" />
									</button>
									<button type="button" :disabled="getColorRampStops(selectedNode).length <= 2" @click="removeColorRampStop(selectedNode, index)" v-tooltip="'Delete stop'">
										<i class="mdi mdi-delete-outline" />
									</button>
								</div>
							</div>
							<button type="button" class="shader-graph__add-stop" @click="addColorRampStop(selectedNode)">
								<i class="mdi mdi-plus" /> Add Stop
							</button>
						</div>

						<div v-if="selectedNodeDef.inputs.length" class="shader-graph__field-group">
							<h4>Input Defaults</h4>
							<label
								v-for="port in selectedNodeDef.inputs"
								:key="port.key"
								class="shader-graph__field"
								:class="{ 'shader-graph__field--connected': isNodeInputConnected(selectedNode, port.key) }"
							>
								<span>
									{{ port.label }}
									<em>{{ port.type }}</em>
									<small v-if="isNodeInputConnected(selectedNode, port.key)">connected</small>
								</span>
								<input
									v-if="port.type === 'float'"
									type="number"
									:step="getNumericInputStep(port)"
									:disabled="isNodeInputConnected(selectedNode, port.key)"
									:value="getShaderInputDefault(selectedNode, port)"
									@input="setNodeInputDefault(selectedNode, port.key, ($event.target as HTMLInputElement).value || '0.0')"
								/>
								<div v-else-if="port.type === 'vec2'" class="shader-graph__vector-input">
									<label v-for="(_, index) in 2" :key="index">
										<span>{{ VECTOR_COMPONENT_LABELS[index] }}</span>
										<input
											type="number"
											step="0.01"
											:disabled="isNodeInputConnected(selectedNode, port.key)"
											:value="vecDefaultComponent(getShaderInputDefault(selectedNode, port), index, 'vec2')"
											@input="setVecInputDefaultComponent(selectedNode, port.key, index, ($event.target as HTMLInputElement).value || '0.0', 'vec2')"
										/>
									</label>
								</div>
								<div v-else-if="port.type === 'vec3' && canEditPortAsColor(selectedNode, port)" class="shader-graph__color-input">
									<input
										type="color"
										:disabled="isNodeInputConnected(selectedNode, port.key)"
										:value="vec3DefaultToHex(getShaderInputDefault(selectedNode, port))"
										@input="setNodeInputDefault(selectedNode, port.key, hexToVec3(($event.target as HTMLInputElement).value))"
									/>
									<div class="shader-graph__vector-input">
										<label v-for="(_, index) in 3" :key="index">
											<span>{{ VECTOR_COMPONENT_LABELS[index] }}</span>
											<input
												type="number"
												step="0.01"
												min="0"
												max="1"
												:disabled="isNodeInputConnected(selectedNode, port.key)"
												:value="vecDefaultComponent(getShaderInputDefault(selectedNode, port), index, 'vec3')"
												@input="setVecInputDefaultComponent(selectedNode, port.key, index, ($event.target as HTMLInputElement).value || '0.0', 'vec3')"
											/>
										</label>
									</div>
								</div>
								<div v-else-if="port.type === 'vec3'" class="shader-graph__vector-input">
									<label v-for="(_, index) in 3" :key="index">
										<span>{{ VECTOR_COMPONENT_LABELS[index] }}</span>
										<input
											type="number"
											step="0.01"
											:disabled="isNodeInputConnected(selectedNode, port.key)"
											:value="vecDefaultComponent(getShaderInputDefault(selectedNode, port), index, 'vec3')"
											@input="setVecInputDefaultComponent(selectedNode, port.key, index, ($event.target as HTMLInputElement).value || '0.0', 'vec3')"
										/>
									</label>
								</div>
								<div v-else-if="port.type === 'vec4'" class="shader-graph__vector-input">
									<label v-for="(_, index) in 4" :key="index">
										<span>{{ VECTOR_COMPONENT_LABELS[index] }}</span>
										<input
											type="number"
											step="0.01"
											:disabled="isNodeInputConnected(selectedNode, port.key)"
											:value="vecDefaultComponent(getShaderInputDefault(selectedNode, port), index, 'vec4')"
											@input="setVecInputDefaultComponent(selectedNode, port.key, index, ($event.target as HTMLInputElement).value || '0.0', 'vec4')"
										/>
									</label>
								</div>
								<input
									v-else
									type="text"
									:disabled="isNodeInputConnected(selectedNode, port.key)"
									:value="getShaderInputDefault(selectedNode, port)"
									@input="setNodeInputDefault(selectedNode, port.key, ($event.target as HTMLInputElement).value)"
								/>
							</label>
						</div>

						<p v-if="!hasEditableNodeSettings(selectedNode)" class="shader-graph__empty-state">
							This node has no editable settings yet.
						</p>
					</template>
					<p v-else class="shader-graph__empty-state">Select a node to edit its settings.</p>
				</section>

				<section v-else-if="sidePanelTab === 'preview'" class="shader-graph__preview-panel">
					<div class="shader-graph__preview-controls">
						<button type="button" @click="togglePreviewPaused" :disabled="!lastPreviewGlsl">
							<i :class="previewPaused ? 'mdi mdi-play' : 'mdi mdi-pause'" />
							{{ previewPaused ? "Resume" : "Pause" }}
						</button>
						<button type="button" @click="resetPreviewTime" :disabled="!lastPreviewGlsl">
							<i class="mdi mdi-restart" /> Reset Time
						</button>
						<label>
							<i class="mdi mdi-image-filter-center-focus" />
							<select v-model="previewBackground">
								<option value="checker">Checker</option>
								<option value="black">Black</option>
								<option value="transparent">Transparent</option>
							</select>
						</label>
					</div>
					<div
						class="shader-graph__preview-stage"
						:class="`shader-graph__preview-stage--${previewBackground}`"
					>
						<canvas
							ref="livePreviewCanvas"
							class="shader-graph__live-preview"
							width="320"
							height="180"
							@pointermove="updatePreviewMouse"
							@pointerleave="resetPreviewMouse"
						/>
						<div v-if="previewStatus.kind === 'idle'" class="shader-graph__preview-empty">
							<i class="mdi mdi-play-circle-outline" />
						</div>
						<div v-if="previewOverlayMessage" class="shader-graph__preview-overlay">
							<i :class="previewStatus.icon" />
							<span>{{ previewOverlayMessage }}</span>
						</div>
					</div>
					<p
						class="shader-graph__preview-status"
						:class="`shader-graph__preview-status--${previewStatus.kind}`"
					>
						<i :class="previewStatus.icon" /> {{ previewStatus.message }}
					</p>
				</section>

				<section v-else-if="sidePanelTab === 'errors'" class="shader-graph__errors">
					<p v-if="!compileErrors.length" class="shader-graph__empty-state">No shader graph errors.</p>
					<p v-for="(err, i) in compileErrors" v-else :key="i"><i class="mdi mdi-alert" /> {{ err }}</p>
				</section>

				<section v-else class="shader-graph__code">
					<header>
						<strong>{{ compileErrors.length ? "Last Valid GLSL" : "Generated GLSL" }}</strong>
						<button type="button" @click="copyGlsl" v-tooltip="'Copy to clipboard'">
							<i class="mdi mdi-content-copy" />
						</button>
					</header>
					<pre><code>{{ compiledGlsl }}</code></pre>
				</section>
			</aside>
		</div>
	</div>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue"
import {
	CollapsibleContextMenu,
	useIpcCaller,
} from "showrunner-ui-core"
import {
	centerGraphBoundsPan,
	collectRenderedGraphPortPositions,
	evaluateGraphRuntime,
	findNearestGraphPort,
	graphBezierPath,
	graphFitZoom,
	graphPointFromClient,
	graphPortPositionKey,
	graphSkinStyle,
	graphWireId,
	oppositeGraphPortKind,
	resolveGraphWireEndpoints,
	type GraphPortCandidate,
	type GraphPoint,
	type GraphRuntimeAdapter,
	type GraphRuntimeSnapshot,
	type GraphSkinTokens,
} from "../../../../../../libs/showrunner-ui-core/src/util/graph"
import {
	SHADER_NODE_DEFS,
	SHADER_NODE_DEF_MAP,
	SHADER_NODE_CATEGORIES,
	areShaderTypesCompatible,
	collectShaderUniformDefaults,
	compileShaderGraph,
	createShaderNodePreviewGraph,
	normalizeShaderColorRampStops,
	serializeShaderColorRampStops,
	wouldCreateShaderGraphCycle,
	type ShaderGraph,
	type ShaderNodeInstance,
	type ShaderNodeDef,
	type GlslType,
	type ShaderColorRampStop,
	type ShaderUniformValueMap,
} from "./shader-nodes"
import { SHADER_GRAPH_STARTERS, collectShaderUniformBindings, createDefaultShaderGraph, createShaderGraphStarter, cloneShaderGraph, normalizeShaderGraph } from "./shader-graph-state"
import type { ShaderUniformBindingMap } from "showrunner-plugin-overlays-shared"

const props = defineProps<{
	modelValue: ShaderGraph
}>()

const emit = defineEmits<{
	"update:modelValue": [graph: ShaderGraph]
	"compile": [glsl: string, uniforms: ShaderUniformValueMap, bindings: ShaderUniformBindingMap]
	"close": []
}>()

const SHADER_GRAPH_SKIN: GraphSkinTokens = {
	canvasBackground: "#0d0d0d",
	panelBackground: "#111",
	panelBorder: "#333",
	nodeBackground: "#1e1e1e",
	nodeBorder: "#444",
	nodeSelected: "#7c4dff",
	wireDefault: "#fff8",
	wireInvalid: "#ef5350",
	textMuted: "#999",
}
const shaderGraphSkinStyle = graphSkinStyle(SHADER_GRAPH_SKIN)
const shaderGraphRuntime: GraphRuntimeAdapter<ShaderGraph, string> = {
	evaluate: (inputGraph) => {
		const result = compileShaderGraph(inputGraph)
		return {
			output: result.glsl || undefined,
			issues: result.errors.map((message) => ({ severity: "error", message })),
		}
	},
}

// ─── State ───────────────────────────────────────────────────────────
const canvasRef = ref<HTMLElement>()
const paletteInputRef = ref<HTMLInputElement>()
const livePreviewCanvas = ref<HTMLCanvasElement>()
const zoom = ref(1)
const pan = ref({ x: 0, y: 0 })
const showGrid = ref(true)
const snapToGrid = ref(true)
const showMinimap = ref(true)
const selectedNodeId = ref<string>()
const selectedWireId = ref<string>()
const paletteOpen = ref(false)
const palettePos = ref({ x: 0, y: 0 })
const paletteQuery = ref("")
const contextMenuOpenGroups = ref(new Set<string>())
const sidePanelTab = ref<"node" | "preview" | "errors" | "code">("preview")
const compiledGlsl = ref("")
const lastGoodGlsl = ref("")
const compileErrors = ref<string[]>([])
const previewError = ref("")
const shaderQualityPreset = ref<"draft" | "balanced" | "high">("balanced")
const previewResolutionScale = ref(1)
const previewFpsLimit = ref(30)
const previewPaused = ref(false)
const previewBackground = ref<"checker" | "black" | "transparent">("checker")
const selectedStarterId = ref("")
const graphPresetName = ref("")
const selectedGraphPresetName = ref("")
const graphPresets = ref<Record<string, unknown>>({})
type ShaderUniformBindingSource = "none" | "config" | "state"
const VECTOR_COMPONENT_LABELS = ["X", "Y", "Z", "W"] as const
let runtimeSnapshot: GraphRuntimeSnapshot<string> = { issues: [], errorMessages: [], ok: true }
const layoutVersion = ref(0)
let layoutFrame: number | undefined

const previewStatus = computed(() => {
	if (previewError.value) {
		return {
			kind: "error",
			icon: "mdi mdi-alert-circle-outline",
			message: previewError.value,
		}
	}
	if (compileErrors.value.length && lastPreviewGlsl.value) {
		return {
			kind: "stale",
			icon: "mdi mdi-history",
			message: `Graph has errors. Preview is showing the last valid shader: ${compileErrors.value[0]}`,
		}
	}
	if (compileErrors.value.length) {
		return {
			kind: "error",
			icon: "mdi mdi-alert-circle-outline",
			message: compileErrors.value[0],
		}
	}
	if (lastPreviewGlsl.value) {
		return {
			kind: "ok",
			icon: "mdi mdi-check-circle-outline",
			message: "Preview is running from the latest valid compile.",
		}
	}
	return {
		kind: "idle",
		icon: "mdi mdi-information-outline",
		message: "Compile a valid graph to preview it here.",
	}
})

const graphPresetNames = computed(() => Object.keys(graphPresets.value).sort((a, b) => a.localeCompare(b)))
const canSaveGraphPreset = computed(() => graphPresetName.value.trim().length > 0)
const listShaderGraphPresets = useIpcCaller<() => Promise<Record<string, unknown>>>("overlays", "listShaderGraphPresets")
const saveShaderGraphPresetCall = useIpcCaller<(preset: { name: string; graph: ShaderGraph }) => Promise<Record<string, unknown>>>("overlays", "saveShaderGraphPreset")
const deleteShaderGraphPresetCall = useIpcCaller<(name: string) => Promise<Record<string, unknown>>>("overlays", "deleteShaderGraphPreset")

const previewOverlayMessage = computed(() => {
	if (previewError.value) return previewError.value
	if (compileErrors.value.length && lastPreviewGlsl.value) return "Showing the last valid shader while the graph has compile errors."
	if (previewPaused.value && lastPreviewGlsl.value) return "Preview paused."
	return ""
})

// Wire drag state
const dragWire = ref<{ path: string; fromNode: string; fromPort: string; fromKind: "in" | "out"; type: GlslType; color: string; valid: boolean; validationMessage?: string } | null>(null)
let dragState: { fromNode: string; fromPort: string; fromKind: "in" | "out"; fromX: number; fromY: number; type: GlslType } | null = null

// Node preview canvases
const previewRefs = new Map<string, HTMLCanvasElement>()
function setPreviewRef(nodeId: string, el: HTMLCanvasElement | null) {
	if (el) {
		previewRefs.set(nodeId, el)
		nextTick(renderNodePreviews)
	}
	else previewRefs.delete(nodeId)
}

// ─── Computed ────────────────────────────────────────────────────────
const graph = computed({
	get: () => props.modelValue,
	set: (v) => emit("update:modelValue", v),
})

const undoStack = ref<ShaderGraph[]>([])
const redoStack = ref<ShaderGraph[]>([])
let isApplyingHistory = false
let lastHistoryKey = ""
const canUndo = computed(() => undoStack.value.length > 1)
const canRedo = computed(() => redoStack.value.length > 0)

function emitGraphUpdate() {
	const snapshot = cloneShaderGraph(graph.value)
	emit("update:modelValue", snapshot)
	recordGraphHistory(snapshot)
}

function graphHistoryKey(source: ShaderGraph) {
	return JSON.stringify(source)
}

function recordGraphHistory(source: ShaderGraph) {
	if (isApplyingHistory) return
	const snapshot = cloneShaderGraph(source)
	const key = graphHistoryKey(snapshot)
	if (key === lastHistoryKey) return
	undoStack.value = [...undoStack.value, snapshot].slice(-80)
	redoStack.value = []
	lastHistoryKey = key
}

function applyGraphHistory(snapshot: ShaderGraph) {
	isApplyingHistory = true
	graph.value = cloneShaderGraph(snapshot)
	emit("update:modelValue", cloneShaderGraph(snapshot))
	isApplyingHistory = false
	selectedNodeId.value = undefined
	selectedWireId.value = undefined
	scheduleLayoutRefresh()
	autoCompile()
}

function undoGraph() {
	if (!canUndo.value) return
	const nextUndo = [...undoStack.value]
	const current = nextUndo.pop()
	const previous = nextUndo[nextUndo.length - 1]
	if (!current || !previous) return
	undoStack.value = nextUndo
	redoStack.value = [cloneShaderGraph(current), ...redoStack.value].slice(0, 80)
	lastHistoryKey = graphHistoryKey(previous)
	applyGraphHistory(previous)
}

function redoGraph() {
	const [next, ...rest] = redoStack.value
	if (!next) return
	redoStack.value = rest
	undoStack.value = [...undoStack.value, cloneShaderGraph(next)].slice(-80)
	lastHistoryKey = graphHistoryKey(next)
	applyGraphHistory(next)
}

interface GraphNode extends ShaderNodeInstance {
	name: string
	icon: string
	category: string
	inputs: ShaderNodeDef["inputs"]
	outputs: ShaderNodeDef["outputs"]
}

const graphNodes = computed<GraphNode[]>(() =>
	graph.value.nodes.map((n) => {
		const def = SHADER_NODE_DEF_MAP.get(n.defId)
		return {
			...n,
			name: def?.name ?? n.defId,
			icon: def?.icon ?? "mdi mdi-help",
			category: def?.category ?? "Unknown",
			inputs: def?.inputs ?? [],
			outputs: def?.outputs ?? [],
		}
	})
)

const selectedNode = computed(() => graph.value.nodes.find((node) => node.id === selectedNodeId.value))
const selectedNodeDef = computed(() => selectedNode.value ? SHADER_NODE_DEF_MAP.get(selectedNode.value.defId) : undefined)
const zoomLabel = computed(() => `${Math.round(zoom.value * 100)}%`)

const NODE_W = 180

const surfaceSize = computed(() => ({
	width: Math.max(1600, ...graphNodes.value.map((n) => n.x + NODE_W + 200)),
	height: Math.max(900, ...graphNodes.value.map((n) => n.y + 200)),
}))

const minimapNodes = computed(() =>
	graphNodes.value.map((node) => ({
		id: node.id,
		x: (node.x / surfaceSize.value.width) * 100,
		y: (node.y / surfaceSize.value.height) * 100,
		width: (NODE_W / surfaceSize.value.width) * 100,
		height: (120 / surfaceSize.value.height) * 100,
	}))
)

const minimapViewport = computed(() => {
	const canvas = canvasRef.value
	if (!canvas) return { x: 0, y: 0, width: 100, height: 100 }
	const x = (-pan.value.x / zoom.value / surfaceSize.value.width) * 100
	const y = (-pan.value.y / zoom.value / surfaceSize.value.height) * 100
	const width = (canvas.clientWidth / zoom.value / surfaceSize.value.width) * 100
	const height = (canvas.clientHeight / zoom.value / surfaceSize.value.height) * 100
	return {
		x: Math.max(0, Math.min(100, x)),
		y: Math.max(0, Math.min(100, y)),
		width: Math.max(4, Math.min(100, width)),
		height: Math.max(4, Math.min(100, height)),
	}
})

const renderedPortPositions = computed(() => {
	layoutVersion.value
	const surface = canvasRef.value?.querySelector<HTMLElement>(".shader-graph__surface")
	if (!surface) return new Map<string, GraphPoint>()
	return collectShaderPortPositions(surface)
})

function getPortPos(nodeId: string, portKey: string, kind: "in" | "out"): { x: number; y: number } | undefined {
	const rendered = renderedPortPositions.value.get(graphPortPositionKey(nodeId, portKey, kind))
	if (rendered) return rendered

	const node = graphNodes.value.find((n) => n.id === nodeId)
	if (!node) return undefined
	const def = SHADER_NODE_DEF_MAP.get(node.defId)
	if (!def) return undefined
	const ports = kind === "in" ? def.inputs : def.outputs
	const idx = ports.findIndex((p) => p.key === portKey)
	if (idx < 0) return undefined

	const headerH = 28
	const previewH = (node.defId !== "float_const" && node.defId !== "vec3_const") ? 80 : 0
	const portStartY = headerH + previewH + 8
	const portH = 20
	const y = node.y + portStartY + idx * portH + portH / 2

	return {
		x: kind === "in" ? node.x : node.x + NODE_W,
		y,
	}
}

const wirePaths = computed(() =>
	graph.value.wires.flatMap((wire) => {
		const from = getPortPos(wire.fromNode, wire.fromPort, "out")
		const to = getPortPos(wire.toNode, wire.toPort, "in")
		if (!from || !to) return []
		const fromDef = SHADER_NODE_DEF_MAP.get(graphNodes.value.find((n) => n.id === wire.fromNode)?.defId ?? "")
		const portDef = fromDef?.outputs.find((p) => p.key === wire.fromPort)
		return [{
			id: wire.id,
			path: shaderWirePath(from.x, from.y, to.x, to.y),
			color: typeColor(portDef?.type ?? "float"),
		}]
	})
)

const inputPaletteDefs = computed(() =>
	SHADER_NODE_DEFS.filter((def) => def.category === "Input")
)

const contextMenuCategories = computed(() =>
	SHADER_NODE_CATEGORIES
		.map((cat) => ({
			name: cat,
			defs: SHADER_NODE_DEFS.filter((def) => def.category === cat),
		}))
		.filter((cat) => cat.defs.length > 0)
)

const contextMenuQueryResults = computed(() => {
	const query = paletteQuery.value.toLowerCase().trim()
	if (!query) return []
	return SHADER_NODE_DEFS.filter((def) =>
		def.name.toLowerCase().includes(query) ||
		def.category.toLowerCase().includes(query) ||
		def.id.toLowerCase().includes(query)
	)
})

watch(
	() => graph.value.nodes.map((node) => `${node.id}:${node.defId}:${node.x}:${node.y}`).join("|"),
	scheduleLayoutRefresh,
	{ flush: "post" }
)

// ─── Pan / Zoom ──────────────────────────────────────────────────────
function onZoom(e: WheelEvent) {
	const step = 0.08
	setZoom(zoom.value + (e.deltaY > 0 ? -step : step))
}

function setZoom(value: number) {
	zoom.value = Math.max(0.25, Math.min(2, value))
	scheduleLayoutRefresh()
}

function zoomIn() {
	setZoom(zoom.value + 0.1)
}

function zoomOut() {
	setZoom(zoom.value - 0.1)
}

function snapCoordinate(value: number) {
	if (!snapToGrid.value) return Math.round(value)
	return Math.round(value / 32) * 32
}

function onCanvasPointerDown(e: PointerEvent) {
	if (e.button === 1) {
		e.preventDefault()
		startPan(e)
	}
	if (e.button === 0) {
		selectedNodeId.value = undefined
		selectedWireId.value = undefined
		if (paletteOpen.value) paletteOpen.value = false
	}
}

function startPan(e: PointerEvent) {
	const startX = e.clientX
	const startY = e.clientY
	const startPanX = pan.value.x
	const startPanY = pan.value.y
	function onMove(me: PointerEvent) {
		pan.value = { x: startPanX + me.clientX - startX, y: startPanY + me.clientY - startY }
	}
	function onUp() {
		window.removeEventListener("pointermove", onMove)
		window.removeEventListener("pointerup", onUp)
	}
	window.addEventListener("pointermove", onMove)
	window.addEventListener("pointerup", onUp)
}

function fitGraph() {
	const canvas = canvasRef.value
	if (!canvas || graphNodes.value.length === 0) return
	const minX = Math.min(...graphNodes.value.map((n) => n.x))
	const minY = Math.min(...graphNodes.value.map((n) => n.y))
	const maxX = Math.max(...graphNodes.value.map((n) => n.x + NODE_W))
	const maxY = Math.max(...graphNodes.value.map((n) => n.y + 160))
	const cw = canvas.clientWidth
	const ch = canvas.clientHeight
	const bounds = { minX, minY, width: maxX - minX, height: maxY - minY }
	zoom.value = graphFitZoom(bounds, { width: cw, height: ch }, { padding: 80, maxZoom: 1 })
	pan.value = centerGraphBoundsPan(bounds, { width: cw, height: ch }, zoom.value)
	scheduleLayoutRefresh()
}

function fitSelection() {
	const node = graphNodes.value.find((item) => item.id === selectedNodeId.value)
	const canvas = canvasRef.value
	if (!node || !canvas) return
	const bounds = { minX: node.x, minY: node.y, width: NODE_W, height: 160 }
	zoom.value = graphFitZoom(bounds, { width: canvas.clientWidth, height: canvas.clientHeight }, { padding: 140, maxZoom: 1.25 })
	pan.value = centerGraphBoundsPan(bounds, { width: canvas.clientWidth, height: canvas.clientHeight }, zoom.value)
	scheduleLayoutRefresh()
}

// ─── Node Drag ───────────────────────────────────────────────────────
function startNodeDrag(e: PointerEvent, node: GraphNode) {
	selectNode(node.id)
	const startX = e.clientX
	const startY = e.clientY
	const startNodeX = node.x
	const startNodeY = node.y
	const target = e.currentTarget as HTMLElement
	target.setPointerCapture(e.pointerId)
	function onMove(me: PointerEvent) {
		const dx = (me.clientX - startX) / zoom.value
		const dy = (me.clientY - startY) / zoom.value
		const n = graph.value.nodes.find((nd) => nd.id === node.id)
		if (n) {
			n.x = Math.max(0, snapCoordinate(startNodeX + dx))
			n.y = Math.max(0, snapCoordinate(startNodeY + dy))
			scheduleLayoutRefresh()
		}
	}
	function onUp() {
		target.removeEventListener("pointermove", onMove)
		target.removeEventListener("pointerup", onUp)
		emitGraphUpdate()
		autoCompile()
	}
	target.addEventListener("pointermove", onMove)
	target.addEventListener("pointerup", onUp)
}

// ─── Wire Drag ───────────────────────────────────────────────────────
function startWireDrag(e: PointerEvent, nodeId: string, portKey: string, kind: "in" | "out", type: GlslType) {
	e.preventDefault()
	const pos = getPortPos(nodeId, portKey, kind)
	if (!pos) return

	// If dragging from input that has a wire, disconnect and reverse
	if (kind === "in") {
		const idx = graph.value.wires.findIndex((w) => w.toNode === nodeId && w.toPort === portKey)
		if (idx >= 0) {
			const wire = graph.value.wires[idx]
			graph.value.wires.splice(idx, 1)
			const fromPos = getPortPos(wire.fromNode, wire.fromPort, "out")
			if (fromPos) {
				dragState = { fromNode: wire.fromNode, fromPort: wire.fromPort, fromKind: "out", fromX: fromPos.x, fromY: fromPos.y, type }
				dragWire.value = createDragWirePreview(dragState, pos, { valid: true })
				addWireDragListeners()
				return
			}
		}
	}

	dragState = { fromNode: nodeId, fromPort: portKey, fromKind: kind, fromX: pos.x, fromY: pos.y, type }
	dragWire.value = createDragWirePreview(dragState, pos, { valid: true })
	addWireDragListeners()
}

function addWireDragListeners() {
	window.addEventListener("pointermove", onWireMove, true)
	window.addEventListener("pointerup", onWireUp, true)
	window.addEventListener("pointercancel", onWireUp, true)
}

function removeWireDragListeners() {
	window.removeEventListener("pointermove", onWireMove, true)
	window.removeEventListener("pointerup", onWireUp, true)
	window.removeEventListener("pointercancel", onWireUp, true)
}

function onWireMove(e: PointerEvent) {
	if (!dragState || !canvasRef.value) return
	const surface = canvasRef.value.querySelector<HTMLElement>(".shader-graph__surface")
	if (!surface) return
	const point = graphPointFromClient(surface, e.clientX, e.clientY, zoom.value)
	const target = findShaderPortAtClientPoint(e.clientX, e.clientY, oppositeGraphPortKind(dragState.fromKind)) ?? findNearestShaderPort(dragState, point, false)
	const validation = target ? validateShaderWireTarget(dragState, target) : { valid: true }
	dragWire.value = createDragWirePreview(dragState, point, validation)
}

function onWireUp(e: PointerEvent) {
	removeWireDragListeners()
	if (!dragState) { dragWire.value = null; return }

	// Find port under cursor
	const surface = canvasRef.value?.querySelector<HTMLElement>(".shader-graph__surface")
	if (!surface) { dragWire.value = null; dragState = null; return }
	const point = graphPointFromClient(surface, e.clientX, e.clientY, zoom.value)
	let connected = false

	const target = findShaderPortAtClientPoint(e.clientX, e.clientY, oppositeGraphPortKind(dragState.fromKind)) ?? findNearestShaderPort(dragState, point, false)
	if (target) {
		const validation = validateShaderWireTarget(dragState, target)
		if (validation.valid) {
			const endpoints = resolveGraphWireEndpoints(dragState, target)
			const nextWire = { id: graphWireId(endpoints), ...endpoints }
			const nextWires = graph.value.wires.filter((w) => !(w.toNode === endpoints.toNode && w.toPort === endpoints.toPort))
			graph.value.wires = [...nextWires, nextWire]
			emitGraphUpdate()
			autoCompile()
			connected = true
		} else {
			compileErrors.value = [validation.message ?? "Shader wire cannot connect to that port."]
			previewError.value = compileErrors.value[0]
			connected = true
		}
	}

	if (!connected) {
		emitGraphUpdate()
		autoCompile()
	}
	dragWire.value = null
	dragState = null
}

function getShaderPortCandidates(targetKind: "in" | "out"): GraphPortCandidate[] {
	const candidates: GraphPortCandidate[] = []
	for (const node of graphNodes.value) {
		const ports = targetKind === "in" ? node.inputs : node.outputs
		for (const port of ports) {
			const position = getPortPos(node.id, port.key, targetKind)
			if (!position) continue
			candidates.push({ nodeId: node.id, portKey: port.key, kind: targetKind, position })
		}
	}
	return candidates
}

function findNearestShaderPort(drag: NonNullable<typeof dragState>, point: GraphPoint, compatibleOnly: boolean) {
	const targetKind = oppositeGraphPortKind(drag.fromKind)
	const snap = 40 / zoom.value
	return findNearestGraphPort(
		point,
		getShaderPortCandidates(targetKind),
		snap,
		(candidate) => candidate.nodeId !== drag.fromNode && (!compatibleOnly || validateShaderWireTarget(drag, candidate).valid)
	)
}

function findShaderPortAtClientPoint(clientX: number, clientY: number, expectedKind: "in" | "out"): GraphPortCandidate | undefined {
	const element = document
		.elementFromPoint(clientX, clientY)
		?.closest<HTMLElement>("[data-shader-port-node-id]")
	if (!element) return undefined
	const nodeId = element.dataset.shaderPortNodeId
	const portKey = element.dataset.shaderPortKey
	const kind = element.dataset.shaderPortKind
	if (!nodeId || !portKey || kind !== expectedKind) return undefined
	const position = getPortPos(nodeId, portKey, expectedKind)
	if (!position) return undefined
	return { nodeId, portKey, kind: expectedKind, position }
}

function createDragWirePreview(
	drag: NonNullable<typeof dragState>,
	point: GraphPoint,
	validation: { valid: boolean; message?: string }
) {
	const isOut = drag.fromKind === "out"
	return {
		path: isOut
			? shaderWirePath(drag.fromX, drag.fromY, point.x, point.y)
			: shaderWirePath(point.x, point.y, drag.fromX, drag.fromY),
		fromNode: drag.fromNode,
		fromPort: drag.fromPort,
		fromKind: drag.fromKind,
		type: drag.type,
		color: validation.valid ? typeColor(drag.type) : SHADER_GRAPH_SKIN.wireInvalid,
		valid: validation.valid,
		validationMessage: validation.message,
	}
}

function validateShaderWireTarget(drag: NonNullable<typeof dragState>, target: GraphPortCandidate) {
	const endpoints = resolveGraphWireEndpoints(drag, target)
	const sourcePort = getShaderPortDef(endpoints.fromNode, endpoints.fromPort, "out")
	const targetPort = getShaderPortDef(endpoints.toNode, endpoints.toPort, "in")
	if (!sourcePort) return { valid: false, message: "Source port is missing." }
	if (!targetPort) return { valid: false, message: "Target port is missing." }
	if (!areShaderTypesCompatible(sourcePort.type, targetPort.type)) {
		return { valid: false, message: `Incompatible shader wire: ${sourcePort.type} -> ${targetPort.type}.` }
	}
	const nextWires = graph.value.wires.filter((wire) => !(wire.toNode === endpoints.toNode && wire.toPort === endpoints.toPort))
	if (wouldCreateShaderGraphCycle({ ...graph.value, wires: nextWires }, endpoints.fromNode, endpoints.toNode)) {
		return { valid: false, message: `Connecting ${endpoints.fromNode}:${endpoints.fromPort} to ${endpoints.toNode}:${endpoints.toPort} would create a cycle.` }
	}
	return { valid: true }
}

function getShaderPortDef(nodeId: string, portKey: string, kind: "in" | "out") {
	const node = graphNodes.value.find((item) => item.id === nodeId)
	const ports = kind === "in" ? node?.inputs : node?.outputs
	return ports?.find((port) => port.key === portKey)
}

function selectNode(nodeId: string) {
	selectedNodeId.value = nodeId
	selectedWireId.value = undefined
	sidePanelTab.value = "node"
}

function getNodeInputDefault(node: ShaderNodeInstance, key: string, fallback: string) {
	const value = node.inputDefaults?.[key]
	return value == null ? fallback : String(value)
}

function setNodeInputDefault(node: ShaderNodeInstance, key: string, value: string) {
	node.inputDefaults = { ...(node.inputDefaults ?? {}), [key]: value }
	emitGraphUpdate()
	autoCompile()
}

function hasEditableNodeSettings(node: ShaderNodeInstance) {
	const def = SHADER_NODE_DEF_MAP.get(node.defId)
	return ["float_const", "vec3_const", "uniform_float", "uniform_vec2", "uniform_vec3", "comment_frame"].includes(node.defId) || Boolean(def?.inputs.length)
}

function isUniformParameterNode(node: ShaderNodeInstance) {
	return node.defId === "uniform_float" || node.defId === "uniform_vec2" || node.defId === "uniform_vec3"
}

function getUniformBindingSource(node: ShaderNodeInstance): ShaderUniformBindingSource {
	const source = node.inputDefaults?.bindingSource
	return source === "config" || source === "state" ? source : "none"
}

function setUniformBindingSource(node: ShaderNodeInstance, value: string) {
	const source: ShaderUniformBindingSource = value === "config" || value === "state" ? value : "none"
	if (source === "none") {
		const { bindingSource, bindingPath, bindingPlugin, bindingState, ...rest } = node.inputDefaults ?? {}
		node.inputDefaults = rest
	} else {
		node.inputDefaults = { ...(node.inputDefaults ?? {}), bindingSource: source }
	}
	emitGraphUpdate()
	autoCompile()
}

function isNodeInputConnected(node: ShaderNodeInstance, portKey: string) {
	return graph.value.wires.some((wire) => wire.toNode === node.id && wire.toPort === portKey)
}

function getShaderInputDefault(node: ShaderNodeInstance, port: ShaderNodeDef["inputs"][number]) {
	return getNodeInputDefault(node, port.key, port.default ?? glslInputFallback(port.type))
}

function canEditPortAsColor(node: ShaderNodeInstance, port: ShaderNodeDef["inputs"][number]) {
	const identity = `${port.key} ${port.label}`.toLowerCase()
	return port.type === "vec3" && (identity.includes("color") || /^vec3\s*\(/.test(getShaderInputDefault(node, port)))
}

function getNumericInputStep(port: ShaderNodeDef["inputs"][number]) {
	const identity = `${port.key} ${port.label}`.toLowerCase()
	if (identity.includes("octave") || identity.includes("step")) return "1"
	if (identity.includes("seed")) return "1"
	return "0.01"
}

function glslInputFallback(type: GlslType) {
	switch (type) {
		case "float": return "0.0"
		case "vec2": return "vec2(0.0)"
		case "vec3": return "vec3(0.0)"
		case "vec4": return "vec4(0.0, 0.0, 0.0, 1.0)"
	}
}

function vec3DefaultToHex(value: string) {
	const parts = value.match(/[-+]?\d*\.?\d+/g)?.map(Number) ?? []
	const [r = 1, g = 1, b = 1] = parts
	return `#${[r, g, b].map((part) => Math.round(Math.max(0, Math.min(1, part)) * 255).toString(16).padStart(2, "0")).join("")}`
}

function hexToVec3(hex: string) {
	const normalized = hex.replace("#", "")
	const r = parseInt(normalized.slice(0, 2), 16) / 255
	const g = parseInt(normalized.slice(2, 4), 16) / 255
	const b = parseInt(normalized.slice(4, 6), 16) / 255
	return `vec3(${r.toFixed(3)}, ${g.toFixed(3)}, ${b.toFixed(3)})`
}

function parseVec2Default(value: string): [number, number] {
	const parts = parseVecDefault(value, 2)
	return [parts[0], parts[1]]
}

function vec2DefaultComponent(value: string, index: 0 | 1) {
	return String(parseVec2Default(value)[index])
}

function setVec2InputDefaultComponent(node: ShaderNodeInstance, key: string, index: 0 | 1, value: string) {
	const parts = parseVec2Default(getNodeInputDefault(node, key, "vec2(0.0, 0.0)"))
	const next = Number(value)
	parts[index] = Number.isFinite(next) ? next : 0
	setNodeInputDefault(node, key, `vec2(${parts[0].toFixed(3)}, ${parts[1].toFixed(3)})`)
}

function parseVecDefault(value: string, length: number) {
	const parts = value.match(/[-+]?\d*\.?\d+/g)?.map(Number) ?? []
	return Array.from({ length }, (_, index) => Number.isFinite(parts[index]) ? parts[index] : getVecFallbackValue(length, index))
}

function vecDefaultComponent(value: string, index: number, type: Extract<GlslType, "vec2" | "vec3" | "vec4">) {
	return String(parseVecDefault(value, vecLength(type))[index])
}

function setVecInputDefaultComponent(
	node: ShaderNodeInstance,
	key: string,
	index: number,
	value: string,
	type: Extract<GlslType, "vec2" | "vec3" | "vec4">
) {
	const length = vecLength(type)
	const parts = parseVecDefault(getNodeInputDefault(node, key, `${type}(${getVecFallbackValue(length, 0).toFixed(1)})`), length)
	const next = Number(value)
	parts[index] = Number.isFinite(next) ? next : getVecFallbackValue(length, index)
	setNodeInputDefault(node, key, `${type}(${parts.map((part) => part.toFixed(3)).join(", ")})`)
}

function vecLength(type: Extract<GlslType, "vec2" | "vec3" | "vec4">) {
	if (type === "vec2") return 2
	if (type === "vec3") return 3
	return 4
}

function getVecFallbackValue(length: number, index: number) {
	if (length === 4 && index === 3) return 1
	return 0
}

function getColorRampStops(node: ShaderNodeInstance) {
	return normalizeShaderColorRampStops(node.inputDefaults?.rampStops)
}

function setColorRampStops(node: ShaderNodeInstance, stops: ShaderColorRampStop[]) {
	node.inputDefaults = { ...(node.inputDefaults ?? {}), rampStops: serializeShaderColorRampStops(stops) }
	emitGraphUpdate()
	autoCompile()
}

function setColorRampStopColor(node: ShaderNodeInstance, index: number, color: string) {
	const stops = getColorRampStops(node)
	if (!stops[index]) return
	stops[index] = { ...stops[index], color: hexToVec3(color) }
	setColorRampStops(node, stops)
}

function setColorRampStopOffset(node: ShaderNodeInstance, index: number, value: string) {
	const stops = getColorRampStops(node)
	if (!stops[index]) return
	const offset = Math.max(0, Math.min(1, Number(value)))
	stops[index] = { ...stops[index], offset: Number.isFinite(offset) ? offset : stops[index].offset }
	setColorRampStops(node, stops)
}

function addColorRampStop(node: ShaderNodeInstance) {
	const stops = getColorRampStops(node)
	const midpoint = getLargestRampGapMidpoint(stops)
	const color = getInterpolatedRampColor(stops, midpoint)
	setColorRampStops(node, [...stops, { offset: midpoint, color }])
}

function removeColorRampStop(node: ShaderNodeInstance, index: number) {
	const stops = getColorRampStops(node)
	if (stops.length <= 2) return
	stops.splice(index, 1)
	setColorRampStops(node, stops)
}

function moveColorRampStop(node: ShaderNodeInstance, index: number, direction: -1 | 1) {
	const stops = getColorRampStops(node)
	const target = index + direction
	if (!stops[index] || !stops[target]) return
	const next = [...stops]
	;[next[index], next[target]] = [next[target], next[index]]
	setColorRampStops(node, next.map((stop, nextIndex) => ({ ...stop, offset: stops[nextIndex].offset })))
}

function colorRampPreview(node: ShaderNodeInstance) {
	const stops = getColorRampStops(node)
	return `linear-gradient(to right, ${stops.map((stop) => `${vec3DefaultToHex(stop.color)} ${(stop.offset * 100).toFixed(1)}%`).join(", ")})`
}

function getLargestRampGapMidpoint(stops: ShaderColorRampStop[]) {
	const sorted = [...stops].sort((a, b) => a.offset - b.offset)
	let bestStart = 0
	let bestEnd = 1
	let bestGap = -1
	for (let i = 1; i < sorted.length; i++) {
		const gap = sorted[i].offset - sorted[i - 1].offset
		if (gap > bestGap) {
			bestGap = gap
			bestStart = sorted[i - 1].offset
			bestEnd = sorted[i].offset
		}
	}
	return Number(((bestStart + bestEnd) / 2).toFixed(3))
}

function getInterpolatedRampColor(stops: ShaderColorRampStop[], offset: number) {
	const sorted = [...stops].sort((a, b) => a.offset - b.offset)
	const nextIndex = sorted.findIndex((stop) => stop.offset >= offset)
	const right = sorted[nextIndex] ?? sorted[sorted.length - 1]
	const left = sorted[Math.max(0, nextIndex - 1)] ?? sorted[0]
	const span = Math.max(0.0001, right.offset - left.offset)
	const t = Math.max(0, Math.min(1, (offset - left.offset) / span))
	const a = parseVecDefault(left.color, 3)
	const b = parseVecDefault(right.color, 3)
	return `vec3(${a.map((value, index) => (value + (b[index] - value) * t).toFixed(3)).join(", ")})`
}

function shouldShowNodePreview(node: ShaderNodeInstance) {
	return !["float_const", "vec3_const", "comment_frame"].includes(node.defId)
}

function nodeTitle(node: ShaderNodeInstance & { name: string }) {
	if (node.defId === "comment_frame") {
		const title = typeof node.inputDefaults?.title === "string" ? node.inputDefaults.title.trim() : ""
		return title || node.name
	}
	return node.name
}

// ─── Palette ─────────────────────────────────────────────────────────
function openPalette(e: MouseEvent) {
	palettePos.value = { x: e.clientX - (canvasRef.value?.getBoundingClientRect().left ?? 0), y: e.clientY - (canvasRef.value?.getBoundingClientRect().top ?? 0) }
	paletteQuery.value = ""
	contextMenuOpenGroups.value = new Set()
	paletteOpen.value = true
	nextTick(() => paletteInputRef.value?.focus())
}

function toggleContextGroup(group: string) {
	const next = new Set(contextMenuOpenGroups.value)
	if (next.has(group)) next.delete(group)
	else next.add(group)
	contextMenuOpenGroups.value = next
}

function isContextGroupOpen(group: string) {
	return contextMenuOpenGroups.value.has(group)
}

let nodeCounter = 0
let copiedNode: ShaderNodeInstance | undefined
function addNode(defId: string) {
	addNodeAt(defId, {
		x: Math.round((palettePos.value.x - pan.value.x) / zoom.value),
		y: Math.round((palettePos.value.y - pan.value.y) / zoom.value),
	})
	paletteOpen.value = false
}

function addNodeFromPalette(defId: string) {
	const canvas = canvasRef.value
	const x = canvas ? (canvas.clientWidth * 0.5 - pan.value.x) / zoom.value : 240
	const y = canvas ? (canvas.clientHeight * 0.45 - pan.value.y) / zoom.value : 200
	addNodeAt(defId, { x: Math.round(x), y: Math.round(y) })
}

function addNodeAt(defId: string, position: { x: number; y: number }) {
	if (!canvasRef.value) return
	const id = `sn_${Date.now()}_${nodeCounter++}`
	graph.value.nodes.push({ id, defId, x: Math.max(0, snapCoordinate(position.x)), y: Math.max(0, snapCoordinate(position.y)) })
	if (defId === "fragment_output") graph.value.outputNodeId = id
	emitGraphUpdate()
	scheduleLayoutRefresh()
	autoCompile()
}

function cloneNodeForPaste(node: ShaderNodeInstance, offset = 36): ShaderNodeInstance {
	return {
		id: `sn_${Date.now()}_${nodeCounter++}`,
		defId: node.defId,
		x: node.x + offset,
		y: node.y + offset,
		inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined,
	}
}

function copySelectedNode() {
	const node = selectedNode.value
	if (!node) return
	copiedNode = { ...node, inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined }
}

function pasteCopiedNode() {
	if (!copiedNode) return
	const node = cloneNodeForPaste(copiedNode)
	graph.value.nodes.push(node)
	selectedNodeId.value = node.id
	selectedWireId.value = undefined
	emitGraphUpdate()
	scheduleLayoutRefresh()
	autoCompile()
}

function duplicateSelectedNode() {
	const node = selectedNode.value
	if (!node) return
	copiedNode = { ...node, inputDefaults: node.inputDefaults ? { ...node.inputDefaults } : undefined }
	pasteCopiedNode()
}

// ─── Compile ─────────────────────────────────────────────────────────
function autoCompile() {
	runtimeSnapshot = evaluateGraphRuntime(shaderGraphRuntime, graph.value, lastGoodGlsl.value || undefined)
	compileErrors.value = runtimeSnapshot.errorMessages
	if (!runtimeSnapshot.ok) {
		if (lastGoodGlsl.value && !lastPreviewGlsl.value) updateLivePreview(lastGoodGlsl.value)
		return
	}
	if (runtimeSnapshot.output) {
		compiledGlsl.value = runtimeSnapshot.output
		lastGoodGlsl.value = runtimeSnapshot.lastGoodOutput ?? runtimeSnapshot.output
		currentPreviewUniforms = collectShaderUniformDefaults(graph.value)
		updateLivePreview(runtimeSnapshot.output)
	}
	renderNodePreviews()
}

function compileAndApply() {
	autoCompile()
	if (!compileErrors.value.length && compiledGlsl.value) {
		emit("compile", compiledGlsl.value, collectShaderUniformDefaults(graph.value), collectShaderUniformBindings(graph.value))
		sidePanelTab.value = "preview"
	} else {
		sidePanelTab.value = "errors"
	}
}

function collectShaderPortPositions(surface: HTMLElement) {
	return collectRenderedGraphPortPositions(surface, zoom.value, {
		selector: "[data-shader-port-node-id]",
		nodeIdDatasetKey: "shaderPortNodeId",
		portKeyDatasetKey: "shaderPortKey",
		kindDatasetKey: "shaderPortKind",
	})
}

function scheduleLayoutRefresh() {
	if (layoutFrame != null) cancelAnimationFrame(layoutFrame)
	nextTick(() => {
		layoutFrame = requestAnimationFrame(() => {
			layoutVersion.value += 1
			layoutFrame = undefined
		})
	})
}

function resetGraph() {
	graph.value = createDefaultShaderGraph()
	emitGraphUpdate()
	autoCompile()
	fitGraph()
	scheduleLayoutRefresh()
}

function loadSelectedStarter() {
	if (!selectedStarterId.value) return
	graph.value = createShaderGraphStarter(selectedStarterId.value)
	selectedNodeId.value = undefined
	selectedWireId.value = undefined
	emitGraphUpdate()
	autoCompile()
	fitGraph()
	scheduleLayoutRefresh()
}

async function refreshGraphPresets() {
	graphPresets.value = await listShaderGraphPresets()
}

async function saveGraphPreset() {
	const name = graphPresetName.value.trim()
	if (!name) return
	graphPresets.value = await saveShaderGraphPresetCall({ name, graph: cloneShaderGraph(graph.value) })
	selectedGraphPresetName.value = name
}

function loadSelectedGraphPreset() {
	const preset = graphPresets.value[selectedGraphPresetName.value]
	if (!preset) return
	graph.value = normalizeShaderGraph(preset)
	selectedNodeId.value = undefined
	selectedWireId.value = undefined
	emitGraphUpdate()
	autoCompile()
	fitGraph()
	scheduleLayoutRefresh()
}

async function deleteSelectedGraphPreset() {
	const name = selectedGraphPresetName.value.trim()
	if (!name) return
	graphPresets.value = await deleteShaderGraphPresetCall(name)
	selectedGraphPresetName.value = ""
}

function layoutGraphByCategory() {
	const categoryOrder = ["Input", "Noise", "Terrain", "Vector", "Math", "Color", "Lighting", "Camera", "Utility", "Output"]
	const buckets = new Map<string, ShaderNodeInstance[]>()
	for (const node of graph.value.nodes) {
		const category = SHADER_NODE_DEF_MAP.get(node.defId)?.category ?? "Utility"
		const key = categoryOrder.includes(category) ? category : "Utility"
		if (!buckets.has(key)) buckets.set(key, [])
		buckets.get(key)!.push(node)
	}

	let column = 0
	for (const category of categoryOrder) {
		const nodes = buckets.get(category)
		if (!nodes?.length) continue
		nodes.sort((a, b) => a.y - b.y || a.x - b.x)
		nodes.forEach((node, row) => {
			node.x = 64 + column * 260
			node.y = 80 + row * 180
		})
		column += 1
	}
	emitGraphUpdate()
	fitGraph()
	scheduleLayoutRefresh()
	autoCompile()
}

function copyGlsl() {
	const source = compiledGlsl.value || lastGoodGlsl.value
	if (source) navigator.clipboard.writeText(source).catch(() => {})
}

// ─── Keyboard ────────────────────────────────────────────────────────
function onKeyDown(e: KeyboardEvent) {
	if (e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === "z") {
		e.preventDefault()
		undoGraph()
		return
	}
	if ((e.ctrlKey && e.shiftKey && e.key.toLowerCase() === "z") || (e.ctrlKey && e.key.toLowerCase() === "y")) {
		e.preventDefault()
		redoGraph()
		return
	}
	if (e.ctrlKey && e.key.toLowerCase() === "c" && selectedNode.value) {
		e.preventDefault()
		copySelectedNode()
		return
	}
	if (e.ctrlKey && e.key.toLowerCase() === "v" && copiedNode) {
		e.preventDefault()
		pasteCopiedNode()
		return
	}
	if (e.ctrlKey && e.key.toLowerCase() === "d" && selectedNode.value) {
		e.preventDefault()
		duplicateSelectedNode()
		return
	}
	if ((e.key === "Delete" || e.key === "Backspace") && selectedWireId.value) {
		e.preventDefault()
		const idx = graph.value.wires.findIndex((w) => w.id === selectedWireId.value)
		if (idx >= 0) graph.value.wires.splice(idx, 1)
		selectedWireId.value = undefined
		emitGraphUpdate()
		autoCompile()
	}
	if ((e.key === "Delete" || e.key === "Backspace") && selectedNodeId.value) {
		e.preventDefault()
		const nodeId = selectedNodeId.value
		if (nodeId && graph.value.nodes.find((n) => n.id === nodeId)?.defId !== "fragment_output") {
			graph.value.nodes = graph.value.nodes.filter((n) => n.id !== nodeId)
			graph.value.wires = graph.value.wires.filter((w) => w.fromNode !== nodeId && w.toNode !== nodeId)
			selectedNodeId.value = undefined
			emitGraphUpdate()
			autoCompile()
		}
	}
}

onMounted(() => {
	window.addEventListener("keydown", onKeyDown)
	refreshGraphPresets()
	recordGraphHistory(graph.value)
	scheduleLayoutRefresh()
	autoCompile()
})
onUnmounted(() => {
	window.removeEventListener("keydown", onKeyDown)
	if (layoutFrame != null) cancelAnimationFrame(layoutFrame)
	disposePreview()
})

// ─── Live Preview ────────────────────────────────────────────────────
let previewGl: WebGLRenderingContext | null = null
let previewProgram: WebGLProgram | null = null
let previewBuffer: WebGLBuffer | null = null
let previewCanvas: HTMLCanvasElement | null = null
let previewFrame = 0
let previewStartedAt = 0
let previewPausedAt = 0
let lastPreviewRenderAt = 0
let currentPreviewUniforms: ShaderUniformValueMap = {}
let previewMouse = { x: 0, y: 0 }
const lastPreviewGlsl = ref("")

function updateLivePreview(glsl: string) {
	const canvas = livePreviewCanvas.value
	if (!canvas) return
	if (previewCanvas !== canvas) {
		disposePreview()
		previewCanvas = canvas
	}
	if (!previewGl) {
		previewGl = canvas.getContext("webgl", { alpha: true })
		if (!previewGl) {
			previewError.value = "WebGL preview is not available in this view."
			return
		}
		previewBuffer = previewGl.createBuffer()
		previewGl.bindBuffer(previewGl.ARRAY_BUFFER, previewBuffer)
		previewGl.bufferData(previewGl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), previewGl.STATIC_DRAW)
	}
	try {
		const prog = compileProgram(previewGl, glsl)
		if (previewProgram) previewGl.deleteProgram(previewProgram)
		previewProgram = prog
		previewStartedAt = performance.now()
		previewPausedAt = 0
		previewPaused.value = false
		lastPreviewGlsl.value = glsl
		previewError.value = ""
		resizePreviewCanvas(canvas)
		resetPreviewMouse()
		cancelAnimationFrame(previewFrame)
		renderPreview()
	} catch (error) {
		previewError.value = error instanceof Error ? error.message : String(error)
	}
}

function renderNodePreviews() {
	nextTick(() => {
		for (const [nodeId, canvas] of previewRefs) {
			const previewGraph = createShaderNodePreviewGraph(graph.value, nodeId)
			if (!previewGraph) {
				paintNodePreviewFallback(canvas, "#101010", "no output")
				continue
			}
			const result = compileShaderGraph(previewGraph)
			if (result.errors.length || !result.glsl) {
				paintNodePreviewFallback(canvas, "#2d1111", "error")
				continue
			}
			try {
				renderStaticShaderPreview(canvas, result.glsl, collectShaderUniformDefaults(previewGraph))
			} catch {
				paintNodePreviewFallback(canvas, "#101010", "preview")
			}
		}
	})
}

function renderStaticShaderPreview(canvas: HTMLCanvasElement, glsl: string, uniforms: ShaderUniformValueMap) {
	const gl = canvas.getContext("webgl", { alpha: true, preserveDrawingBuffer: true })
	if (!gl) throw new Error("WebGL preview is not available.")
	const buffer = gl.createBuffer()
	const program = compileProgram(gl, glsl)
	if (!buffer) {
		gl.deleteProgram(program)
		throw new Error("Could not create preview buffer.")
	}
	gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW)
	gl.viewport(0, 0, canvas.width, canvas.height)
	gl.clearColor(0, 0, 0, 0)
	gl.clear(gl.COLOR_BUFFER_BIT)
	gl.useProgram(program)
	const posLoc = gl.getAttribLocation(program, "a_position")
	gl.enableVertexAttribArray(posLoc)
	gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0)
	gl.uniform2f(gl.getUniformLocation(program, "u_resolution"), canvas.width, canvas.height)
		gl.uniform1f(gl.getUniformLocation(program, "u_time"), 1.25)
	gl.uniform2f(gl.getUniformLocation(program, "u_mouse"), canvas.width * 0.5, canvas.height * 0.5)
	gl.uniform3fv(gl.getUniformLocation(program, "u_accent"), [0.57, 0.27, 1.0])
	gl.uniform3fv(gl.getUniformLocation(program, "u_secondary"), [0, 0.82, 1.0])
	gl.uniform1f(gl.getUniformLocation(program, "u_intensity"), 0.8)
	gl.uniform1f(gl.getUniformLocation(program, "u_speed"), 1.0)
	gl.uniform3fv(gl.getUniformLocation(program, "u_camera_position"), [0, 0, 2.5])
	gl.uniform3fv(gl.getUniformLocation(program, "u_camera_target"), [0, 0, 0])
	applyUniformValues(gl, program, uniforms)
	gl.drawArrays(gl.TRIANGLES, 0, 6)
	gl.deleteBuffer(buffer)
	gl.deleteProgram(program)
}

function paintNodePreviewFallback(canvas: HTMLCanvasElement, background: string, label: string) {
	const ctx = canvas.getContext("2d")
	if (!ctx) return
	ctx.clearRect(0, 0, canvas.width, canvas.height)
	ctx.fillStyle = background
	ctx.fillRect(0, 0, canvas.width, canvas.height)
	ctx.fillStyle = "#888"
	ctx.font = "11px sans-serif"
	ctx.textAlign = "center"
	ctx.textBaseline = "middle"
	ctx.fillText(label, canvas.width / 2, canvas.height / 2)
}

function disposePreview() {
	cancelAnimationFrame(previewFrame)
	if (previewGl) {
		if (previewProgram) previewGl.deleteProgram(previewProgram)
		if (previewBuffer) previewGl.deleteBuffer(previewBuffer)
	}
	previewGl = null
	previewProgram = null
	previewBuffer = null
	previewCanvas = null
}

function stopPreview() {
	disposePreview()
	lastPreviewGlsl.value = ""
	previewError.value = ""
	previewPaused.value = false
	previewPausedAt = 0
}

watch(sidePanelTab, (tab) => {
	if (tab !== "preview") return
	nextTick(() => {
		if (lastPreviewGlsl.value) updateLivePreview(lastPreviewGlsl.value)
		else autoCompile()
	})
})

function renderPreview() {
	const gl = previewGl
	const prog = previewProgram
	const canvas = livePreviewCanvas.value
	if (!gl || !prog || !canvas) return
	const now = performance.now()
	if (previewPaused.value) {
		previewFrame = requestAnimationFrame(renderPreview)
		return
	}
	const frameMs = 1000 / Math.max(previewFpsLimit.value || 30, 1)
	if (lastPreviewRenderAt && now - lastPreviewRenderAt < frameMs) {
		previewFrame = requestAnimationFrame(renderPreview)
		return
	}
	lastPreviewRenderAt = now
	resizePreviewCanvas(canvas)
	gl.viewport(0, 0, canvas.width, canvas.height)
	gl.clearColor(0, 0, 0, 0)
	gl.clear(gl.COLOR_BUFFER_BIT)
	gl.useProgram(prog)
	const posLoc = gl.getAttribLocation(prog, "a_position")
	gl.enableVertexAttribArray(posLoc)
	gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0)
	gl.uniform2f(gl.getUniformLocation(prog, "u_resolution"), canvas.width, canvas.height)
	gl.uniform1f(gl.getUniformLocation(prog, "u_time"), previewElapsedSeconds(now))
	gl.uniform2f(gl.getUniformLocation(prog, "u_mouse"), previewMouse.x, previewMouse.y)
	gl.uniform3fv(gl.getUniformLocation(prog, "u_accent"), [0.57, 0.27, 1.0])
	gl.uniform3fv(gl.getUniformLocation(prog, "u_secondary"), [0, 0.82, 1.0])
	gl.uniform1f(gl.getUniformLocation(prog, "u_intensity"), 0.8)
	gl.uniform1f(gl.getUniformLocation(prog, "u_speed"), 1.0)
	gl.uniform3fv(gl.getUniformLocation(prog, "u_camera_position"), [0, 0, 2.5])
	gl.uniform3fv(gl.getUniformLocation(prog, "u_camera_target"), [0, 0, 0])
	applyUniformValues(gl, prog, currentPreviewUniforms)
	gl.drawArrays(gl.TRIANGLES, 0, 6)
	previewFrame = requestAnimationFrame(renderPreview)
}

function previewElapsedSeconds(now = performance.now()) {
	return ((previewPaused.value && previewPausedAt ? previewPausedAt : now) - previewStartedAt) / 1000
}

function togglePreviewPaused() {
	if (!lastPreviewGlsl.value) return
	if (previewPaused.value) {
		const pausedSeconds = previewElapsedSeconds()
		previewStartedAt = performance.now() - pausedSeconds * 1000
		previewPausedAt = 0
		previewPaused.value = false
		renderPreview()
		return
	}
	previewPausedAt = performance.now()
	previewPaused.value = true
}

function resetPreviewTime() {
	previewStartedAt = performance.now()
	previewPausedAt = 0
	previewPaused.value = false
	lastPreviewRenderAt = 0
	if (lastPreviewGlsl.value) renderPreview()
}

function resizePreviewCanvas(canvas: HTMLCanvasElement) {
	const ratio = Math.max(1, Math.min(window.devicePixelRatio || 1, 2)) * previewResolutionScale.value
	const width = Math.max(1, Math.round(canvas.clientWidth * ratio))
	const height = Math.max(1, Math.round(canvas.clientHeight * ratio))
	if (canvas.width !== width || canvas.height !== height) {
		canvas.width = width
		canvas.height = height
	}
}

function applyQualityPreset() {
	switch (shaderQualityPreset.value) {
		case "draft":
			previewResolutionScale.value = 0.5
			previewFpsLimit.value = 20
			break
		case "high":
			previewResolutionScale.value = 1.25
			previewFpsLimit.value = 60
			break
		default:
			previewResolutionScale.value = 1
			previewFpsLimit.value = 30
			break
	}
	lastPreviewRenderAt = 0
}

function updatePreviewMouse(event: PointerEvent) {
	const canvas = livePreviewCanvas.value
	if (!canvas) return
	const rect = canvas.getBoundingClientRect()
	const ratioX = canvas.width / Math.max(rect.width, 1)
	const ratioY = canvas.height / Math.max(rect.height, 1)
	previewMouse = {
		x: (event.clientX - rect.left) * ratioX,
		y: (rect.bottom - event.clientY) * ratioY,
	}
}

function resetPreviewMouse() {
	const canvas = livePreviewCanvas.value
	previewMouse = {
		x: (canvas?.width ?? 0) * 0.5,
		y: (canvas?.height ?? 0) * 0.5,
	}
}

function applyUniformValues(gl: WebGLRenderingContext, prog: WebGLProgram, uniforms: ShaderUniformValueMap) {
	for (const [name, value] of Object.entries(uniforms)) {
		const location = gl.getUniformLocation(prog, name)
		if (!location) continue
		if (typeof value === "number") gl.uniform1f(location, value)
		else if (value.length === 2) gl.uniform2fv(location, value)
		else if (value.length === 3) gl.uniform3fv(location, value)
		else if (value.length === 4) gl.uniform4fv(location, value)
	}
}

const vertexSrc = `attribute vec2 a_position; void main() { gl_Position = vec4(a_position, 0.0, 1.0); }`

function compileProgram(gl: WebGLRenderingContext, fragmentSrc: string): WebGLProgram {
	const vs = gl.createShader(gl.VERTEX_SHADER)!
	gl.shaderSource(vs, vertexSrc)
	gl.compileShader(vs)
	if (!gl.getShaderParameter(vs, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(vs) ?? "VS error")
	const fs = gl.createShader(gl.FRAGMENT_SHADER)!
	gl.shaderSource(fs, fragmentSrc)
	gl.compileShader(fs)
	if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(fs) ?? "FS error")
	const prog = gl.createProgram()!
	gl.attachShader(prog, vs)
	gl.attachShader(prog, fs)
	gl.linkProgram(prog)
	gl.deleteShader(vs)
	gl.deleteShader(fs)
	if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog) ?? "Link error")
	return prog
}

// ─── Utils ───────────────────────────────────────────────────────────
function shaderWirePath(x1: number, y1: number, x2: number, y2: number): string {
	return graphBezierPath(x1, y1, x2, y2, { minControl: 50 })
}

function typeColor(type: GlslType): string {
	switch (type) {
		case "float": return "#4fc3f7"
		case "vec2": return "#7986cb"
		case "vec3": return "#81c784"
		case "vec4": return "#9575cd"
	}
}

function categoryColor(cat: string): string {
	switch (cat) {
		case "Input": return "#2e7d32"
		case "Math": return "#1565c0"
		case "Vector": return "#6a1b9a"
		case "Color": return "#c62828"
		case "Noise": return "#6d4c41"
		case "Terrain": return "#558b2f"
		case "Lighting": return "#f9a825"
		case "Camera": return "#00838f"
		case "Utility": return "#455a64"
		case "Output": return "#e65100"
		default: return "#37474f"
	}
}
</script>

<style scoped>
.shader-graph {
	background: var(--graph-canvas-background);
	color: #e0e0e0;
	display: flex;
	flex: 1;
	flex-direction: column;
	height: 100%;
	min-height: 0;
	min-width: 0;
	overflow: hidden;
	width: 100%;
}

.shader-graph__toolbar {
	align-items: center;
	background: #111;
	border-bottom: 1px solid #333;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
	min-height: 2.25rem;
	padding: 0.4rem 0.8rem;
	position: relative;
	z-index: 2;
}

.shader-graph__toolbar h3 {
	flex: 0 0 auto;
	font-size: 0.95rem;
	font-weight: 600;
	margin: 0;
}

.shader-graph__toolbar-actions {
	align-items: center;
	display: flex;
	flex: 0 0 auto;
	gap: 0.35rem;
	min-width: 0;
	overflow-x: auto;
}

.shader-graph__toolbar-control {
	align-items: center;
	background: #202020;
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	color: #aaa;
	display: flex;
	gap: 0.3rem;
	min-height: 1.75rem;
	padding: 0 0.35rem;
}

.shader-graph__toolbar-control select,
.shader-graph__toolbar-control input {
	background: #181818;
	border: 0;
	color: #ddd;
	font-size: 0.75rem;
	min-width: 0;
	outline: 0;
}

.shader-graph__toolbar-control input {
	width: 3rem;
}

.shader-graph__toolbar-control--preset select {
	width: 8rem;
}

.shader-graph__toolbar-control--preset input {
	width: 7rem;
}

.shader-graph__toolbar-divider {
	background: #333;
	height: 1.75rem;
	margin: 0 0.15rem;
	width: 1px;
}

.shader-graph__zoom-label {
	color: #eee;
	font-size: 0.84rem;
	font-weight: 700;
	min-width: 3.2rem;
	text-align: center;
}

.shader-graph__toolbar-actions button,
.shader-graph__tool-button {
	align-items: center;
	background: #241433;
	border: 1px solid #67428f;
	border-radius: 4px;
	color: #f1e7ff;
	cursor: pointer;
	display: inline-flex;
	font-size: 0.78rem;
	gap: 0.25rem;
	justify-content: center;
	min-height: 2rem;
	min-width: 2rem;
	padding: 0.25rem 0.55rem;
}

.shader-graph__toolbar-actions button:hover {
	background: #35204a;
	border-color: #9c6fd3;
}

.shader-graph__toolbar-actions button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}

.shader-graph__toolbar-actions button.active {
	background: #8f4bd8;
	border-color: #c59cff;
	color: #fff;
}

.shader-graph__tool-button--run {
	background: #2b1746;
	border-color: #b777ff;
}

.shader-graph__toolbar-actions .shader-graph__close {
	background: #333;
	border-color: #555;
	color: #eee;
}

.shader-graph__toolbar-actions .shader-graph__close:hover {
	background: #555;
}

.shader-graph__body {
	display: grid;
	flex: 1;
	grid-template-columns: 220px minmax(0, 1fr) 360px;
	min-height: 0;
	min-width: 0;
	overflow: hidden;
	position: relative;
}

.shader-graph__inputs {
	background: var(--graph-panel-background);
	border-right: 1px solid var(--graph-panel-border);
	display: flex;
	flex-direction: column;
	gap: 0.7rem;
	min-height: 0;
	min-width: 0;
	overflow: hidden;
	padding: 0.6rem;
}

.shader-graph__inputs header {
	border-bottom: 1px solid #2d2d2d;
	display: flex;
	flex-direction: column;
	gap: 0.15rem;
	padding-bottom: 0.55rem;
}

.shader-graph__inputs header strong {
	font-size: 0.82rem;
}

.shader-graph__inputs header span {
	color: #999;
	font-size: 0.68rem;
	line-height: 1.25;
}

.shader-graph__input-list {
	display: flex;
	flex: 1;
	flex-direction: column;
	gap: 0.35rem;
	min-height: 0;
	overflow: auto;
}

.shader-graph__input-list button {
	align-items: center;
	background: #191919;
	border: 1px solid #303030;
	border-radius: 4px;
	color: #ddd;
	cursor: pointer;
	display: grid;
	gap: 0.45rem;
	grid-template-columns: 1.2rem minmax(0, 1fr);
	min-height: 2.4rem;
	padding: 0.4rem 0.5rem;
	text-align: left;
}

.shader-graph__input-list button:hover {
	background: #252525;
	border-color: #3f6f43;
}

.shader-graph__input-list button span {
	display: flex;
	flex-direction: column;
	gap: 0.05rem;
	min-width: 0;
}

.shader-graph__input-list button strong {
	font-size: 0.74rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.shader-graph__input-list button small {
	color: #888;
	font-family: monospace;
	font-size: 0.64rem;
}

.shader-graph__canvas {
	background-color: #101010;
	border: 1px solid #2f2f2f;
	flex: 1;
	margin: 0.65rem;
	min-width: 0;
	overflow: auto;
	position: relative;
}

.shader-graph__canvas--grid {
	background-image: linear-gradient(#202020 1px, transparent 1px), linear-gradient(90deg, #202020 1px, transparent 1px);
	background-size: 42px 42px;
}

.shader-graph__surface {
	position: relative;
	transform-origin: 0 0;
}

.shader-graph__wires {
	height: 100%;
	left: 0;
	pointer-events: none;
	position: absolute;
	top: 0;
	width: 100%;
}

.shader-graph__wire {
	fill: none;
	pointer-events: stroke;
	stroke-linecap: round;
	stroke-width: 2.5px;
	cursor: pointer;
}

.shader-graph__wire.selected {
	stroke-width: 4px;
	filter: drop-shadow(0 0 6px currentColor);
}

.shader-graph__wire--dragging {
	pointer-events: none;
	stroke-dasharray: 6 4;
}

.shader-graph__wire--invalid {
	filter: drop-shadow(0 0 5px rgb(239 83 80 / 0.45));
}

.shader-graph__node {
	background: var(--graph-node-background);
	border: 2px solid var(--graph-node-border);
	border-radius: 6px;
	cursor: grab;
	min-width: 180px;
	overflow: hidden;
	position: absolute;
	width: 180px;
}

.shader-graph__node.selected {
	border-color: var(--graph-node-selected);
	box-shadow: 0 0 12px rgb(124 77 255 / 0.3);
}

.shader-graph__node.output {
	border-color: #e65100;
}

.shader-graph__node-header {
	align-items: center;
	color: white;
	display: flex;
	font-size: 0.75rem;
	font-weight: 600;
	gap: 0.35rem;
	padding: 0.3rem 0.5rem;
}

.shader-graph__node-preview {
	border-bottom: 1px solid #333;
	display: block;
	height: 80px;
	width: 100%;
}

.shader-graph__ports {
	display: flex;
	justify-content: space-between;
	padding: 0.25rem 0;
}

.shader-graph__port-column {
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.shader-graph__port {
	align-items: center;
	display: flex;
	font-size: 0.68rem;
	gap: 0.25rem;
	padding: 0 0.4rem;
}

.shader-graph__port--out {
	justify-content: flex-end;
}

.shader-graph__port-dot {
	border: 2px solid rgba(255, 255, 255, 0.3);
	border-radius: 50%;
	cursor: crosshair;
	flex-shrink: 0;
	height: 10px;
	transition: transform 0.1s;
	width: 10px;
}

.shader-graph__port-dot:hover {
	transform: scale(1.5);
	box-shadow: 0 0 6px 2px currentColor;
}

.shader-graph__port-name {
	color: #ccc;
}

.shader-graph__port-type {
	color: #777;
	font-family: monospace;
	font-size: 0.6rem;
}

.shader-graph__palette-search {
	align-items: center;
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1rem 1fr;
	padding: 0.35rem 0.45rem;
}

.shader-graph__palette-search input {
	background: transparent;
	border: 0;
	color: var(--text-color);
	min-width: 0;
	outline: 0;
}

.shader-graph__palette-list {
	flex: 1;
	max-height: 300px;
	overflow-y: auto;
}

.shader-graph__palette-category {
	background: #222;
	color: #999;
	font-size: 0.65rem;
	font-weight: 700;
	padding: 0.25rem 0.5rem;
	text-transform: uppercase;
}

.shader-graph__palette-list button {
	align-items: center;
	background: transparent;
	border: 0;
	color: #ddd;
	cursor: pointer;
	display: flex;
	font-size: 0.78rem;
	gap: 0.4rem;
	padding: 0.35rem 0.6rem;
	width: 100%;
}

.shader-graph__palette-list button small {
	color: #777;
	font-size: 0.65rem;
	margin-left: auto;
}

.shader-graph__palette-list button:hover {
	background: #2a2a2a;
}

.shader-graph__menu-section {
	border: 1px solid #292929;
	border-radius: 4px;
	margin-bottom: 0.4rem;
	overflow: hidden;
}

.shader-graph__menu-section-header {
	align-items: center;
	background: #1f1f1f;
	border: 0;
	color: #ddd;
	cursor: pointer;
	display: grid;
	font-size: 0.76rem;
	font-weight: 700;
	gap: 0.35rem;
	grid-template-columns: 1rem minmax(0, 1fr) auto;
	padding: 0.45rem 0.55rem;
	width: 100%;
}

.shader-graph__menu-section-header--static {
	cursor: default;
}

.shader-graph__menu-section-header em {
	color: #888;
	font-size: 0.68rem;
	font-style: normal;
	font-weight: 600;
}

.shader-graph__menu-section-header:hover {
	background: #292929;
}

.shader-graph__side-panel {
	background: var(--graph-panel-background);
	border-left: 1px solid var(--graph-panel-border);
	display: flex;
	flex-direction: column;
	min-height: 0;
	min-width: 320px;
	overflow: hidden;
	width: 360px;
}

.shader-graph__tabs {
	background: #1a1a1a;
	border-bottom: 1px solid #333;
	display: flex;
	gap: 0.25rem;
	padding: 0.4rem;
}

.shader-graph__tabs button {
	background: transparent;
	border: 1px solid transparent;
	border-radius: 4px;
	color: #bbb;
	cursor: pointer;
	font-size: 0.72rem;
	padding: 0.3rem 0.45rem;
}

.shader-graph__tabs button.active,
.shader-graph__tabs button:hover {
	background: #2a2a2a;
	border-color: #444;
	color: #fff;
}

.shader-graph__code {
	display: flex;
	flex: 1;
	flex-direction: column;
	min-height: 0;
	overflow: hidden;
}

.shader-graph__code header {
	align-items: center;
	background: #1a1a1a;
	border-bottom: 1px solid #333;
	display: flex;
	justify-content: space-between;
	padding: 0.4rem 0.6rem;
}

.shader-graph__code header button {
	background: transparent;
	border: 0;
	color: #999;
	cursor: pointer;
}

.shader-graph__code pre {
	flex: 1;
	font-size: 0.72rem;
	margin: 0;
	overflow: auto;
	padding: 0.6rem;
	white-space: pre-wrap;
}

.shader-graph__code code {
	color: #81c784;
}

.shader-graph__errors {
	background: #111;
	flex: 1;
	overflow: auto;
	padding: 0.7rem;
}

.shader-graph__errors p {
	color: #ff6b6b;
	font-size: 0.75rem;
	margin: 0.15rem 0;
}

.shader-graph__node-inspector {
	background: #111;
	display: flex;
	flex: 1;
	flex-direction: column;
	gap: 0.75rem;
	overflow: auto;
	padding: 0.7rem;
}

.shader-graph__node-inspector header {
	align-items: center;
	border-bottom: 1px solid #2d2d2d;
	display: flex;
	gap: 0.55rem;
	padding-bottom: 0.65rem;
}

.shader-graph__node-inspector header i {
	color: #d7b7ff;
	font-size: 1.1rem;
}

.shader-graph__node-inspector header div {
	display: flex;
	flex-direction: column;
	gap: 0.1rem;
}

.shader-graph__node-inspector header span {
	color: #888;
	font-size: 0.72rem;
}

.shader-graph__field {
	display: flex;
	flex-direction: column;
	gap: 0.35rem;
}

.shader-graph__field-row {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: repeat(auto-fit, minmax(72px, 1fr));
}

.shader-graph__field-group {
	border-top: 1px solid #2d2d2d;
	display: flex;
	flex-direction: column;
	gap: 0.65rem;
	padding-top: 0.65rem;
}

.shader-graph__field-group h4 {
	color: #eee;
	font-size: 0.78rem;
	margin: 0;
}

.shader-graph__field span {
	align-items: center;
	color: #bbb;
	display: flex;
	font-size: 0.72rem;
	font-weight: 600;
	gap: 0.35rem;
}

.shader-graph__field span em,
.shader-graph__field span small {
	color: #888;
	font-size: 0.68rem;
	font-style: normal;
	font-weight: 500;
}

.shader-graph__field span small {
	margin-left: auto;
}

.shader-graph__field input,
.shader-graph__field select {
	background: #1c1c1c;
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	color: #eee;
	min-height: 2rem;
	padding: 0.25rem 0.45rem;
}

.shader-graph__vector-input {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: repeat(auto-fit, minmax(52px, 1fr));
}

.shader-graph__vector-input label {
	display: flex;
	flex-direction: column;
	gap: 0.2rem;
}

.shader-graph__vector-input span {
	color: #888;
	font-size: 0.65rem;
	font-weight: 700;
}

.shader-graph__color-input {
	display: grid;
	gap: 0.45rem;
}

.shader-graph__color-input > input[type="color"] {
	min-height: 2.25rem;
	padding: 0.15rem;
}

.shader-graph__ramp-preview {
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	height: 1.8rem;
}

.shader-graph__ramp-stop-list {
	display: grid;
	gap: 0.4rem;
}

.shader-graph__ramp-stop {
	align-items: center;
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 2.2rem minmax(4rem, 1fr) 4.2rem repeat(3, 1.8rem);
}

.shader-graph__ramp-stop input[type="color"] {
	height: 2rem;
	min-height: 0;
	padding: 0.1rem;
	width: 2.2rem;
}

.shader-graph__ramp-stop input[type="range"] {
	min-width: 0;
}

.shader-graph__ramp-stop input[type="number"] {
	min-width: 0;
}

.shader-graph__ramp-stop button,
.shader-graph__add-stop {
	align-items: center;
	background: #241433;
	border: 1px solid #67428f;
	border-radius: 4px;
	color: #f1e7ff;
	cursor: pointer;
	display: inline-flex;
	gap: 0.25rem;
	justify-content: center;
	min-height: 1.9rem;
}

.shader-graph__ramp-stop button:disabled {
	cursor: not-allowed;
	opacity: 0.4;
}

.shader-graph__add-stop {
	justify-self: start;
	padding: 0.25rem 0.55rem;
}

.shader-graph__field textarea {
	background: #1c1c1c;
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	color: #eee;
	min-height: 4.5rem;
	padding: 0.45rem;
	resize: vertical;
}

.shader-graph__field input[type="range"] {
	accent-color: #7ac784;
	min-height: 1.35rem;
	padding: 0;
}

.shader-graph__field--connected input {
	color: #777;
	cursor: not-allowed;
	opacity: 0.65;
}

.shader-graph__minimap {
	background: rgba(12, 12, 12, 0.86);
	border: 1px solid #333;
	border-radius: 4px;
	bottom: 0.75rem;
	height: 96px;
	pointer-events: none;
	position: absolute;
	right: 0.75rem;
	width: 160px;
	z-index: 4;
}

.shader-graph__minimap-node {
	background: #4b5563;
	border-radius: 2px;
	position: absolute;
}

.shader-graph__minimap-node.selected {
	background: #a78bfa;
}

.shader-graph__minimap-viewport {
	border: 1px solid #e0b0ff;
	border-radius: 2px;
	position: absolute;
}

.shader-graph__preview-panel {
	background: #111;
	display: flex;
	flex: 1;
	flex-direction: column;
	gap: 0.6rem;
	overflow: auto;
	padding: 0.7rem;
}

.shader-graph__preview-controls {
	align-items: center;
	display: flex;
	flex-wrap: wrap;
	gap: 0.4rem;
}

.shader-graph__preview-controls button,
.shader-graph__preview-controls label {
	align-items: center;
	background: #202020;
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	color: #ddd;
	display: inline-flex;
	font-size: 0.74rem;
	gap: 0.35rem;
	min-height: 1.8rem;
	padding: 0 0.5rem;
}

.shader-graph__preview-controls button {
	cursor: pointer;
}

.shader-graph__preview-controls button:disabled {
	cursor: not-allowed;
	opacity: 0.5;
}

.shader-graph__preview-controls select {
	background: #181818;
	border: 0;
	color: #eee;
	font-size: 0.74rem;
	outline: 0;
}

.shader-graph__preview-stage {
	aspect-ratio: 16/9;
	background-color: #070707;
	border: 1px solid #333;
	position: relative;
	width: 100%;
}

.shader-graph__preview-stage--checker {
	background:
		linear-gradient(45deg, rgba(255, 255, 255, 0.055) 25%, transparent 25%),
		linear-gradient(-45deg, rgba(255, 255, 255, 0.055) 25%, transparent 25%),
		linear-gradient(45deg, transparent 75%, rgba(255, 255, 255, 0.055) 75%),
		linear-gradient(-45deg, transparent 75%, rgba(255, 255, 255, 0.055) 75%);
	background-color: #070707;
	background-position: 0 0, 0 8px, 8px -8px, -8px 0;
	background-size: 16px 16px;
}

.shader-graph__preview-stage--black {
	background: #000;
}

.shader-graph__preview-stage--transparent {
	background: transparent;
}

.shader-graph__live-preview {
	display: block;
	height: 100%;
	width: 100%;
}

.shader-graph__preview-empty {
	align-items: center;
	color: #666;
	display: flex;
	font-size: 2rem;
	inset: 0;
	justify-content: center;
	pointer-events: none;
	position: absolute;
}

.shader-graph__preview-overlay {
	align-items: center;
	background: rgba(20, 8, 8, 0.86);
	border: 1px solid rgba(255, 120, 120, 0.45);
	border-radius: 5px;
	color: #ffd7d7;
	display: flex;
	font-size: 0.76rem;
	gap: 0.45rem;
	left: 0.75rem;
	line-height: 1.35;
	max-width: calc(100% - 1.5rem);
	padding: 0.55rem 0.65rem;
	position: absolute;
	right: 0.75rem;
	top: 0.75rem;
}

.shader-graph__preview-status {
	border-radius: 4px;
	font-size: 0.75rem;
	line-height: 1.35;
	margin: 0;
	padding: 0.5rem;
}

.shader-graph__preview-status--idle {
	background: #161616;
	border: 1px solid #333;
	color: #aaa;
}

.shader-graph__preview-status--ok {
	background: #102417;
	border: 1px solid #265d35;
	color: #9ee6ad;
}

.shader-graph__preview-status--stale {
	background: #2a2410;
	border: 1px solid #66561f;
	color: #ffd879;
}

.shader-graph__preview-status--error {
	background: #2d1111;
	border: 1px solid #661111;
	color: #ff9b9b;
}

.shader-graph__empty-state {
	color: #999 !important;
}
</style>
