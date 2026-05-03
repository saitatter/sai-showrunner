<template>
	<div class="node-automation">
		<header class="node-automation__toolbar">
			<div>
				<p class="node-automation__eyebrow">Automation Flow</p>
				<h2>{{ model.name || "Untitled Automation" }}</h2>
			</div>
		</header>

		<div class="node-automation__body">
			<section
				ref="canvasRef"
				class="node-automation__canvas"
				:class="{ panning: isPanning, 'space-held': spaceHeld }"
				role="application"
				aria-label="Node editor canvas"
				@pointerdown="handleCanvasPointerDown"
				@dragover.prevent="updateGhostNode"
				@dragleave="ghostNode = null"
				@drop.prevent="dropActionOnCanvas"
				@wheel.ctrl.prevent="zoomFromWheel"
				@wheel.shift.exact.prevent="horizontalPan"
				@contextmenu.prevent="openCanvasContextMenu"
			>
				<div class="node-automation__canvas-controls">
					<button type="button" aria-label="Zoom out" @click="setZoom(zoom - ZOOM_STEP, true)" v-tooltip="'Zoom out'">
						<i class="mdi mdi-magnify-minus-outline" />
					</button>
					<span>{{ Math.round(zoom * 100) }}%</span>
					<button type="button" aria-label="Zoom in" @click="setZoom(zoom + ZOOM_STEP, true)" v-tooltip="'Zoom in'">
						<i class="mdi mdi-magnify-plus-outline" />
					</button>
					<button type="button" aria-label="Fit graph" @click="fitGraph" v-tooltip="'Fit graph'">
						<i class="mdi mdi-fit-to-screen-outline" />
					</button>
					<button type="button" aria-label="Fit selection" :disabled="selectedNodeIds.size < 1" @click="fitToSelection" v-tooltip="'Fit to selection'">
						<i class="mdi mdi-select-all" />
					</button>
					<button type="button" aria-label="Reset view" @click="resetView" v-tooltip="'Reset view'">
						<i class="mdi mdi-backup-restore" />
					</button>
					<button
						type="button"
						:class="{ active: snapToGrid }"
						aria-label="Toggle snap to grid"
						@click="toggleSnapToGrid"
						v-tooltip="'Toggle snap to grid'"
					>
						<i class="mdi mdi-grid" />
					</button>
					<button type="button" aria-label="Auto-layout" @click="autoLayout" v-tooltip="'Auto-layout'">
						<i class="mdi mdi-sitemap-outline" />
					</button>
					<button
						type="button"
						aria-label="Align horizontally"
						:disabled="selectedNodeIds.size < 2"
						@click="alignSelectedNodes('horizontal')"
						v-tooltip="'Align selected horizontally'"
					>
						<i class="mdi mdi-align-vertical-center" />
					</button>
					<button
						type="button"
						aria-label="Align vertically"
						:disabled="selectedNodeIds.size < 2"
						@click="alignSelectedNodes('vertical')"
						v-tooltip="'Align selected vertically'"
					>
						<i class="mdi mdi-align-horizontal-center" />
					</button>
					<button
						type="button"
						aria-label="Distribute evenly"
						:disabled="selectedNodeIds.size < 3"
						@click="distributeSelectedNodes"
						v-tooltip="'Distribute selected evenly'"
					>
						<i class="mdi mdi-distribute-horizontal-center" />
					</button>
					<span class="node-automation__control-divider" />
					<button
						type="button"
						:aria-label="isPreviewPlaying ? 'Pause preview playhead' : 'Play preview playhead'"
						@click="togglePlayheadPreview"
						v-tooltip="isPreviewPlaying ? 'Pause preview playhead' : 'Play preview playhead'"
					>
						<i :class="isPreviewPlaying ? 'mdi mdi-pause' : 'mdi mdi-play'" />
					</button>
					<button type="button" aria-label="Reset preview playhead" @click="resetPlayheadPreview" v-tooltip="'Reset preview playhead'">
						<i class="mdi mdi-stop" />
					</button>
					<div class="node-automation__preview-status">
						<div class="node-automation__preview-meter">
							<span :style="{ width: `${playheadProgress}%` }" />
						</div>
						<strong>{{ currentPreviewStep?.node.title || "Preview idle" }}</strong>
						<small>
							<span v-if="currentPreviewRouteLabel">{{ currentPreviewRouteLabel }} • </span>{{ playheadElapsedLabel }} / {{ previewTotalLabel }}
						</small>
					</div>
				</div>

				<div v-if="canvasSearchOpen" class="node-automation__canvas-search" @click.stop @pointerdown.stop>
					<i class="mdi mdi-magnify" />
					<input
						ref="canvasSearchInputRef"
						v-model="canvasSearchQuery"
						type="search"
						placeholder="Find node…"
						@keydown.enter.prevent="cycleSearchResult(1)"
						@keydown.escape.prevent="closeCanvasSearch"
						@keydown.up.prevent="cycleSearchResult(-1)"
						@keydown.down.prevent="cycleSearchResult(1)"
					/>
					<span v-if="canvasSearchResults.length" class="node-automation__search-count">
						{{ canvasSearchIndex + 1 }}/{{ canvasSearchResults.length }}
					</span>
					<span v-else-if="canvasSearchQuery" class="node-automation__search-count">0</span>
					<button type="button" aria-label="Previous" @click="cycleSearchResult(-1)"><i class="mdi mdi-chevron-up" /></button>
					<button type="button" aria-label="Next" @click="cycleSearchResult(1)"><i class="mdi mdi-chevron-down" /></button>
					<button type="button" aria-label="Close" @click="closeCanvasSearch"><i class="mdi mdi-close" /></button>
				</div>

				<div v-if="activeSubgraph" class="node-automation__subgraph-breadcrumb">
					<button type="button" @click="openMainCanvas">
						<i class="mdi mdi-arrow-left" /> Main graph
					</button>
					<span>/</span>
					<strong>{{ activeSubgraph.name || "Unnamed Subgraph" }}</strong>
					<small>{{ activeSubgraph.nodes.length }} nodes, {{ activeSubgraph.dataWires?.length ?? 0 }} data wires</small>
				</div>

				<div v-if="invalidDataWireIssues.length" class="node-automation__wire-health" @click.stop @pointerdown.stop>
					<i class="mdi mdi-alert-circle-outline" />
					<div>
						<strong>{{ invalidDataWireIssues.length }} invalid data wire{{ invalidDataWireIssues.length === 1 ? "" : "s" }}</strong>
						<small>{{ invalidDataWireIssues[0].message }}</small>
					</div>
					<button type="button" @click="selectDataWireIssue(invalidDataWireIssues[0])">Select</button>
					<button type="button" @click="cleanupInvalidDataWires">Clean up</button>
				</div>

				<div
					class="node-automation__surface"
					:style="{
						width: `${canvasSize.width}px`,
						height: `${canvasSize.height}px`,
						transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
					}"
				>
					<div
						v-for="lane in lanes"
						:key="lane.id"
						class="node-automation__lane"
						:class="`node-automation__lane--${lane.kind}`"
						:style="{
							transform: `translate(${lane.x}px, ${lane.y}px)`,
							width: `${lane.width}px`,
							height: `${lane.height}px`,
						}"
					>
						<span>{{ lane.label }}</span>
					</div>

					<svg class="node-automation__edges" :viewBox="viewBox" role="img" aria-label="Node connections">
						<path
							v-for="edge in visibleFlowEdges"
							:key="`${edge.id}:hit`"
							class="node-automation__edge-hit"
							:class="{ active: dropTargetEdgeId === edge.id }"
							:d="edge.path"
							vector-effect="non-scaling-stroke"
							@dragover.prevent.stop="dropTargetEdgeId = edge.id"
							@dragleave.stop="clearDropEdge(edge.id)"
							@drop.prevent.stop="dropActionOnEdge($event, edge)"
							@click.stop="selectFlowEdge(edge.id)"
						/>
						<path
							v-for="edge in visibleFlowEdges"
							:key="`${edge.id}:line`"
							class="node-automation__edge"
							:class="{ active: dropTargetEdgeId === edge.id, selected: selectedEdgeId === edge.id }"
							:d="edge.path"
							vector-effect="non-scaling-stroke"
						/>
						<g
							v-for="edge in visibleFlowEdges.filter((item) => item.label)"
							:key="`${edge.id}:label`"
							class="node-automation__edge-label"
						>
							<rect
								:x="(edge.labelX ?? 0) - ((edge.labelWidth ?? 60) / 2)"
								:y="(edge.labelY ?? 0) - 11"
								:width="edge.labelWidth ?? 60"
								height="22"
								rx="11"
							/>
							<text
								:x="edge.labelX"
								:y="edge.labelY"
								text-anchor="middle"
								dominant-baseline="central"
							>{{ edge.label }}</text>
						</g>

						<!-- Data wires (port-to-port connections) -->
						<path
							v-for="wire in dataWirePaths"
							:key="`dw-hit:${wire.id}`"
							class="node-automation__data-wire-hit"
							:d="wire.path"
							vector-effect="non-scaling-stroke"
							@click.stop="selectDataWire(wire.id)"
						>
							<title>{{ dataWireTitle(wire) }}</title>
						</path>
						<path
							v-for="wire in dataWirePaths"
							:key="`dw:${wire.id}`"
							class="node-automation__data-wire"
							:class="{ selected: selectedDataWireId === wire.id, removing: removingWireIds.has(wire.id), invalid: wire.valid === false }"
							:d="wire.path"
							:stroke="wire.color"
							vector-effect="non-scaling-stroke"
						>
							<title>{{ dataWireTitle(wire) }}</title>
						</path>

						<!-- In-progress wire drag -->
						<path
							v-if="dragWirePath"
							class="node-automation__data-wire node-automation__data-wire--dragging"
							:class="{ invalid: dragWirePath.valid === false }"
							:d="dragWirePath.path"
							:stroke="dragWirePath.color"
							vector-effect="non-scaling-stroke"
						>
							<title>{{ dragWirePath.validationMessage || "Release on a compatible input port to connect." }}</title>
						</path>

						<!-- In-progress execution edge drag -->
						<path
							v-if="execDragWirePath"
							class="node-automation__edge node-automation__edge--dragging"
							:d="execDragWirePath"
							vector-effect="non-scaling-stroke"
						/>

						<template v-for="(guide, gi) in alignmentGuides" :key="`guide-${gi}`">
							<line
								v-if="guide.axis === 'x'"
								class="node-automation__alignment-guide"
								:x1="guide.position"
								:y1="guide.from - 8"
								:x2="guide.position"
								:y2="guide.to + 8"
								vector-effect="non-scaling-stroke"
							/>
							<line
								v-else
								class="node-automation__alignment-guide"
								:x1="guide.from - 8"
								:y1="guide.position"
								:x2="guide.to + 8"
								:y2="guide.position"
								vector-effect="non-scaling-stroke"
							/>
						</template>
					</svg>

					<button
						v-for="node in nodes"
						:key="node.id"
						class="node-automation__node"
						:class="[
							`node-automation__node--${node.kind}`,
							{
								selected: selectedNodeIds.has(node.id),
								missing: node.missing,
								'drop-target': dropTargetNodeId === node.id,
								'preview-active': playheadNodeId === node.id,
								'search-match': canvasSearchMatchIds.has(node.id),
								'search-dimmed': canvasSearchQuery && !canvasSearchMatchIds.has(node.id),
								'test-running': activeTestExecution?.activeIds?.[node.id] != null,
								'test-success': !activeTestExecution?.activeIds?.[node.id] && activeTestExecution?.nodeResults?.[node.id] != null && !activeTestExecution?.nodeErrors?.[node.id],
								'test-error': !!activeTestExecution?.nodeErrors?.[node.id],
							},
						]"
						:style="{ transform: `translate(${node.x}px, ${node.y}px)`, height: `${node.height}px`, width: `${node.width ?? NODE_WIDTH}px` }"
						type="button"
						role="treeitem"
						:aria-selected="selectedNodeIds.has(node.id)"
						:aria-label="`${node.kind} node: ${node.title} — ${node.subtitle}`"
						tabindex="0"
						@pointerdown.stop="startDrag($event, node)"
						@click.stop="selectNode($event, node.id)"
						@dblclick.stop="openSubgraphFromNode(node.id)"
						@contextmenu.prevent.stop="openNodeContext($event, node)"
						@dragover.prevent.stop="dropTargetNodeId = node.id"
						@dragleave.stop="clearDropTarget(node.id)"
						@drop.prevent.stop="dropActionOnNode($event, node)"
					>
						<span
							v-if="node.kind !== 'variable'"
							class="node-automation__handle node-automation__handle--in"
							:class="{ 'connectable': !!activeGraph }"
						/>
						<span class="node-automation__node-icon">
							<i :class="node.icon" />
						</span>
						<span class="node-automation__node-text">
							<strong>{{ node.title }}</strong>
							<small
								v-if="node.kind === 'variable' && inlineEditNodeId === node.id"
								class="node-automation__inline-edit"
							>
								<input
									ref="inlineEditInput"
									type="text"
									:value="node.subtitle"
									@blur="commitInlineEdit($event, node)"
									@keydown.enter="($event.target as HTMLInputElement).blur()"
									@keydown.escape="cancelInlineEdit"
									@pointerdown.stop
									@click.stop
								/>
							</small>
							<small
								v-else
								@dblclick.stop="node.kind === 'variable' && startInlineEdit(node.id)"
							>{{ node.subtitle }}</small>
						</span>
						<span v-if="node.kind === 'trigger'" class="node-automation__node-run" title="Run automation" @click.stop="runMainExecution" v-tooltip="'Run automation'">
							<i class="mdi mdi-play" />
						</span>
						<span v-if="node.badge" class="node-automation__node-badge">{{ node.badge }}</span>
						<span
							v-if="activeTestExecution?.nodeErrors?.[node.id]"
							class="node-automation__test-badge node-automation__test-badge--error"
							:title="activeTestExecution.nodeErrors[node.id]"
						>✗</span>
						<span
							v-else-if="activeTestExecution?.nodeResults?.[node.id] != null"
							class="node-automation__test-badge node-automation__test-badge--ok"
							:title="JSON.stringify(activeTestExecution.nodeResults[node.id], null, 2)"
						>✓</span>
						<span
							v-if="activeTestExecution?.nodeDurations?.[node.id] != null"
							class="node-automation__test-duration"
							:title="`Last test-run duration: ${formatNodeDuration(activeTestExecution.nodeDurations[node.id])}`"
						>{{ formatNodeDuration(activeTestExecution.nodeDurations[node.id]) }}</span>
						<dl v-if="node.configLines?.length" class="node-automation__node-config">
							<div v-for="(line, li) in node.configLines" :key="li" class="node-automation__node-config-line">
								<dt>{{ line.label }}</dt>
								<dd>{{ line.value }}</dd>
							</div>
						</dl>
						<div v-if="node.inputPorts?.length || node.outputPorts?.length" class="node-automation__node-ports">
							<div class="node-automation__port-columns">
								<ul v-if="node.inputPorts?.length" class="node-automation__port-list node-automation__port-list--in">
									<li v-for="port in node.inputPorts" :key="port.key" class="node-automation__port node-automation__port--in">
										<span
											class="node-automation__port-dot node-automation__port-dot--in"
											:class="[{ connected: isPortConnected(node.id, port.key, 'in') }, dataPortDragClass(node.id, port.key, 'in')]"
											:data-port-node-id="node.id"
											:data-port-key="port.key"
											data-port-kind="in"
											:data-port-type="port.type"
											:title="dataPortDragTitle(node.id, port.key, 'in')"
											:style="{ borderColor: portTypeColor(port.type), background: isPortConnected(node.id, port.key, 'in') ? portTypeColor(port.type) : portTypeColor(port.type) + '44' }"
											@pointerdown.stop="startWireDrag(node.id, port.key, 'in', $event)"
										/>
										<span class="node-automation__port-label">{{ port.label }}</span>
										<span class="node-automation__port-type">{{ port.type }}</span>
									</li>
								</ul>
								<ul v-if="node.outputPorts?.length" class="node-automation__port-list node-automation__port-list--out">
									<li v-for="port in node.outputPorts" :key="port.key" class="node-automation__port node-automation__port--out">
										<span class="node-automation__port-type">{{ port.type }}</span>
										<span class="node-automation__port-label">{{ port.label }}</span>
										<span
											v-if="port.type === 'flow'"
											class="node-automation__port-dot node-automation__port-dot--out node-automation__port-dot--exec"
											:class="{ connected: isExecPortConnected(node.id, port.key) }"
											:data-port-node-id="node.id"
											:data-port-key="port.key"
											data-port-kind="out"
											:data-port-type="port.type"
											@pointerdown.stop="startExecEdgeDrag(node.id, port.key, $event)"
										/>
										<span
											v-else
											class="node-automation__port-dot node-automation__port-dot--out"
											:class="[{ connected: isPortConnected(node.id, port.key, 'out') }, dataPortDragClass(node.id, port.key, 'out')]"
											:data-port-node-id="node.id"
											:data-port-key="port.key"
											data-port-kind="out"
											:data-port-type="port.type"
											:title="dataPortDragTitle(node.id, port.key, 'out')"
											:style="{ borderColor: portTypeColor(port.type), background: isPortConnected(node.id, port.key, 'out') ? portTypeColor(port.type) : portTypeColor(port.type) + '44' }"
											@pointerdown.stop="startWireDrag(node.id, port.key, 'out', $event)"
										/>
									</li>
								</ul>
							</div>
						</div>
						<span
							v-if="canStartFlowFromNode(node)"
							class="node-automation__handle node-automation__handle--out"
							:class="{ 'connectable': !!activeGraph }"
							title="Drag to connect to another node"
							@pointerdown.stop="activeGraph && startExecEdgeDrag(node.id, undefined, $event)"
						/>
						<span
							class="node-automation__resize-handle"
							@pointerdown.stop="startResize($event, node)"
						/>
					</button>

					<div
						v-if="ghostNode"
						class="node-automation__ghost-node"
						:style="{
							transform: `translate(${ghostNode.x}px, ${ghostNode.y}px)`,
						}"
					>
						<i class="mdi mdi-plus" />
						<span>Drop here</span>
					</div>

					<div
						v-if="rubberBand"
						class="node-automation__rubber-band"
						:style="{
							transform: `translate(${rubberBand.x}px, ${rubberBand.y}px)`,
							width: `${rubberBand.width}px`,
							height: `${rubberBand.height}px`,
						}"
					/>
				</div>

				<div
					v-if="contextMenu.open"
					ref="contextMenuRootRef"
					class="node-automation__context-menu-anchor"
					@keydown="handleContextMenuKeydown"
				>
					<collapsible-context-menu
						:x="contextMenu.x"
						:y="contextMenu.y"
						:title="contextMenu.nodeId ? 'Node Menu' : 'Canvas Menu'"
						:subtitle="contextMenuSubtitle"
						@close="closeContextMenu"
					>
						<template #search>
							<label class="node-automation__context-menu-search">
								<i class="mdi mdi-magnify" />
								<input v-model="contextMenuQuery" type="search" placeholder="Search triggers or actions..." />
							</label>
						</template>
					<section v-if="recentContextItems.length && !contextMenuQuery" class="node-automation__menu-section">
						<div class="node-automation__menu-section-header" style="cursor: default; font-size: 0.8rem; opacity: 0.7;">
							<span><i class="mdi mdi-history" /> Recently Used</span>
						</div>
						<div class="node-automation__menu-items">
							<button v-for="item in recentContextItems" :key="`recent-${item.key}`" type="button" @click="item.kind === 'trigger' ? selectTriggerFromContext(item.key) : selectActionFromContext(item.key)">
								<i :class="item.icon" :style="{ color: item.color }" />
								<span>
									<strong>{{ item.name }}</strong>
								</span>
								<em :class="item.kind === 'trigger' ? 'trigger' : ''">{{ item.kind === 'trigger' ? 'Trigger' : 'Action' }}</em>
							</button>
						</div>
					</section>
					<section v-if="contextMenuSearchResults.length" class="node-automation__menu-section">
						<div class="node-automation__menu-section-header" style="cursor: default; font-size: 0.8rem; opacity: 0.7;">
							<span><i class="mdi mdi-filter-variant" /> Matching Nodes</span>
						</div>
						<div class="node-automation__menu-items">
							<button v-for="item in contextMenuSearchResults" :key="`search-${item.kind}-${item.key}`" type="button" @click="selectContextSearchResult(item)">
								<i :class="item.icon" :style="{ color: item.color }" />
								<span>
									<strong>{{ item.name }}</strong>
									<small>{{ item.detail }}</small>
								</span>
								<em :class="item.kind === 'trigger' ? 'trigger' : ''">{{ item.label }}</em>
							</button>
						</div>
					</section>
					<section v-else-if="hiddenPluginSearchHint" class="node-automation__menu-section node-automation__menu-hint">
						<i class="mdi mdi-eye-off-outline" />
						<span>{{ hiddenPluginSearchHint }}</span>
					</section>
					<section v-if="actionCategoryGroups.length" class="node-automation__menu-section">
						<button type="button" class="node-automation__menu-section-header" data-context-section="categories" :aria-expanded="isContextGroupOpen('categories')" @click="toggleContextGroup('categories')">
							<span><i class="mdi mdi-shape-outline" /> Categories</span>
							<i :class="isContextGroupOpen('categories') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="isContextGroupOpen('categories')" class="node-automation__menu-groups">
							<div v-for="group in actionCategoryGroups" :key="group.id" class="node-automation__menu-group">
								<button type="button" class="node-automation__menu-group-header" :aria-expanded="isContextGroupOpen(`category:${group.id}`)" @click="toggleContextGroup(`category:${group.id}`)">
									<span>
										<i :class="group.icon" :style="{ color: group.color }" />
										{{ group.name }}
									</span>
									<i :class="isContextGroupOpen(`category:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
								</button>
								<div v-if="isContextGroupOpen(`category:${group.id}`)" class="node-automation__menu-items">
									<button v-for="item in group.items" :key="`category-${group.id}-${item.key}`" type="button" @click="selectActionFromContext(item.key)">
										<i :class="item.icon" :style="{ color: item.color }" />
										<span>
											<strong>{{ item.name }}</strong>
											<small>{{ item.pluginName }}</small>
										</span>
										<em>Action</em>
									</button>
								</div>
							</div>
						</div>
					</section>
					<!-- Integrations: Triggers + Actions grouped by plugin -->
					<section class="node-automation__menu-section">
						<button type="button" class="node-automation__menu-section-header" data-context-section="integrations" :aria-expanded="isContextGroupOpen('integrations')" @click="toggleContextGroup('integrations')">
							<span><i class="mdi mdi-puzzle-outline" /> Integrations</span>
							<i :class="isContextGroupOpen('integrations') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="isContextGroupOpen('integrations')">
							<!-- Triggers sub-section -->
							<section v-if="!pendingFlowConnection" class="node-automation__menu-section" style="border: 0; border-radius: 0;">
								<button type="button" class="node-automation__menu-section-header" :aria-expanded="isContextGroupOpen('triggers')" @click="toggleContextGroup('triggers')">
									<span><i class="mdi mdi-flash" /> Triggers</span>
									<i :class="isContextGroupOpen('triggers') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
								</button>
								<div v-if="isContextGroupOpen('triggers')" class="node-automation__menu-groups">
									<div v-for="group in triggerContextGroups" :key="group.id" class="node-automation__menu-group">
										<button type="button" class="node-automation__menu-group-header" :aria-expanded="isContextGroupOpen(`trigger:${group.id}`)" @click="toggleContextGroup(`trigger:${group.id}`)">
											<span>
												<i :class="group.icon" :style="{ color: group.color }" />
												{{ group.name }}
											</span>
											<i :class="isContextGroupOpen(`trigger:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
										</button>
										<div v-if="isContextGroupOpen(`trigger:${group.id}`)" class="node-automation__menu-items">
											<button v-for="item in group.items" :key="item.key" type="button" @click="selectTriggerFromContext(item.key)">
												<i :class="item.icon" :style="{ color: item.color }" />
												<span>
													<strong>{{ item.name }}</strong>
													<small>{{ item.pluginName }}</small>
												</span>
												<em class="trigger">Trigger</em>
											</button>
										</div>
									</div>
								</div>
							</section>
							<!-- Actions sub-section -->
							<section class="node-automation__menu-section" style="border: 0; border-radius: 0;">
								<button type="button" class="node-automation__menu-section-header" :aria-expanded="isContextGroupOpen('actions')" @click="toggleContextGroup('actions')">
									<span><i class="mdi mdi-play-circle-outline" /> Actions</span>
									<i :class="isContextGroupOpen('actions') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
								</button>
								<div v-if="isContextGroupOpen('actions')" class="node-automation__menu-groups">
									<div v-for="group in actionContextGroups" :key="group.id" class="node-automation__menu-group">
										<button type="button" class="node-automation__menu-group-header" :aria-expanded="isContextGroupOpen(`action:${group.id}`)" @click="toggleContextGroup(`action:${group.id}`)">
											<span>
												<i :class="group.icon" :style="{ color: group.color }" />
												{{ group.name }}
											</span>
											<i :class="isContextGroupOpen(`action:${group.id}`) ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
										</button>
										<div v-if="isContextGroupOpen(`action:${group.id}`)" class="node-automation__menu-items">
											<button v-for="item in group.items" :key="item.key" type="button" @click="selectActionFromContext(item.key)">
												<i :class="item.icon" :style="{ color: item.color }" />
												<span>
													<strong>{{ item.name }}</strong>
													<small>{{ item.pluginName }}</small>
												</span>
												<em>Action</em>
											</button>
										</div>
									</div>
								</div>
							</section>
						</div>
					</section>
					<!-- Data: Variables + Constants -->
					<section v-if="!pendingFlowConnection" class="node-automation__menu-section">
						<button type="button" class="node-automation__menu-section-header" data-context-section="data" :aria-expanded="isContextGroupOpen('data')" @click="toggleContextGroup('data')">
							<span><i class="mdi mdi-database-outline" /> Data</span>
							<i :class="isContextGroupOpen('data') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="isContextGroupOpen('data')">
							<div v-if="conversionContextItems.length" class="node-automation__menu-subtitle">
								<i class="mdi mdi-swap-horizontal" />
								<span>Conversions</span>
							</div>
							<div v-if="conversionContextItems.length" class="node-automation__menu-items">
								<button v-for="item in conversionContextItems" :key="`conversion-${item.key}`" type="button" @click="selectActionFromContext(item.key)">
									<i :class="item.icon" :style="{ color: item.color }" />
									<span>
										<strong>{{ item.name }}</strong>
										<small>{{ item.pluginName }}</small>
									</span>
									<em>Convert</em>
								</button>
							</div>
							<div class="node-automation__menu-subtitle">
								<i class="mdi mdi-variable" />
								<span>Variables</span>
							</div>
							<div class="node-automation__menu-items">
								<button type="button" @click="addVariableNode('string')">
									<i class="mdi mdi-format-text" style="color: #81c784" />
									<span><strong>String Variable</strong></span>
									<em>Variable</em>
								</button>
								<button type="button" @click="addVariableNode('number')">
									<i class="mdi mdi-numeric" style="color: #4fc3f7" />
									<span><strong>Number Variable</strong></span>
									<em>Variable</em>
								</button>
								<button type="button" @click="addVariableNode('boolean')">
									<i class="mdi mdi-toggle-switch-outline" style="color: #ffb74d" />
									<span><strong>Boolean Variable</strong></span>
									<em>Variable</em>
								</button>
								<button type="button" @click="addVariableNode('color')">
									<i class="mdi mdi-palette" style="color: #f06292" />
									<span><strong>Color Variable</strong></span>
									<em>Variable</em>
								</button>
							</div>
						</div>
					</section>
					<!-- Flow: Control Flow Nodes + Subgraphs -->
					<section class="node-automation__menu-section">
						<button type="button" class="node-automation__menu-section-header" data-context-section="flow" :aria-expanded="isContextGroupOpen('flow')" @click="toggleContextGroup('flow')">
							<span><i class="mdi mdi-vector-polyline" /> Flow</span>
							<i :class="isContextGroupOpen('flow') ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="isContextGroupOpen('flow')">
							<div class="node-automation__menu-items">
								<button type="button" @click="addControlFlowNode('if')">
									<i class="mdi mdi-source-branch" style="color: #64b5f6" />
									<span><strong>If / Else</strong><small>Conditional branch</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('switch')">
									<i class="mdi mdi-source-fork" style="color: #64b5f6" />
									<span><strong>Switch</strong><small>Multi-way branch</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('for')">
									<i class="mdi mdi-repeat" style="color: #68d391" />
									<span><strong>For Loop</strong><small>Counter-based loop</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('forEach')">
									<i class="mdi mdi-format-list-numbered" style="color: #68d391" />
									<span><strong>For Each</strong><small>Iterate over collection</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('while')">
									<i class="mdi mdi-sync" style="color: #68d391" />
									<span><strong>While Loop</strong><small>Condition-based loop</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('break')">
									<i class="mdi mdi-debug-step-out" style="color: #ef9a9a" />
									<span><strong>Break</strong><small>Exit current loop</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('continue')">
									<i class="mdi mdi-skip-next" style="color: #ef9a9a" />
									<span><strong>Continue</strong><small>Next iteration</small></span>
									<em>Control</em>
								</button>
								<button type="button" @click="addControlFlowNode('return')">
									<i class="mdi mdi-keyboard-return" style="color: #ef9a9a" />
									<span><strong>Return</strong><small>End execution</small></span>
									<em>Control</em>
								</button>
								<hr style="border: none; border-top: 1px solid #333; margin: 6px 0;" />
								<template v-if="subgraphsList.length">
									<button v-for="sg in subgraphsList" :key="`sg-${sg.id}`" type="button" @click="addSubgraphCallNode(sg.id)">
										<i class="mdi mdi-function" style="color: #ce93d8" />
										<span><strong>{{ sg.name || 'Unnamed' }}</strong><small>Call subgraph</small></span>
										<em>Subgraph</em>
									</button>
									<hr style="border: none; border-top: 1px solid #333; margin: 6px 0;" />
								</template>
							</div>
						</div>
					</section>
					</collapsible-context-menu>
				</div>
				<datalist id="node-expression-suggestions">
					<option v-for="item in expressionSuggestions" :key="item" :value="item" />
				</datalist>
				<svg
					class="node-automation__minimap"
					:viewBox="minimapViewBox"
					preserveAspectRatio="xMidYMid meet"
					@pointerdown.stop="startMinimapNav"
				>
					<rect
						v-for="node in nodes"
						:key="`mm-${node.id}`"
						:x="node.x"
						:y="node.y"
						:width="NODE_WIDTH"
						:height="node.height"
						:class="`node-automation__minimap-node--${node.kind}`"
						rx="3"
					/>
					<path
						v-for="edge in edges"
						:key="`mm-${edge.id}`"
						:d="edge.path"
						class="node-automation__minimap-edge"
						fill="none"
					/>
					<!-- Data wires on minimap -->
					<path
						v-for="wire in dataWirePaths"
						:key="`mm-dw-${wire.id}`"
						:d="wire.path"
						class="node-automation__minimap-data-wire"
						:stroke="wire.color"
						fill="none"
					/>
					<rect
						class="node-automation__minimap-viewport"
						:x="minimapViewport.x"
						:y="minimapViewport.y"
						:width="minimapViewport.width"
						:height="minimapViewport.height"
						rx="2"
					/>
				</svg>
			</section>

			<aside class="node-automation__details" :class="{ empty: !selectedNode }">
				<header class="node-automation__details-header">
					<div>
						<p class="node-automation__eyebrow">{{ selectedNode ? "Node Context" : "Flow Map" }}</p>
						<h3>{{ selectedNode?.title || "Select a node" }}</h3>
					</div>
					<button
						v-if="selectedNode"
						class="node-automation__icon-button"
						type="button"
						aria-label="Close context"
						@click="clearSelection()"
						v-tooltip="'Close context'"
					>
						<i class="mdi mdi-close" />
					</button>
				</header>

				<template v-if="selectedNode">
					<section class="node-automation__context-section">
						<button type="button" class="node-automation__context-header" :aria-expanded="detailsOpen" @click="detailsOpen = !detailsOpen">
							<span><i class="mdi mdi-information-outline" /> Details</span>
							<i :class="detailsOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<dl v-if="detailsOpen">
							<div>
								<dt>Type</dt>
								<dd>{{ selectedNode.kind }}</dd>
							</div>
							<div>
								<dt>Source</dt>
								<dd>{{ selectedNode.subtitle }}</dd>
							</div>
							<div v-if="selectedNode.path">
								<dt>Path</dt>
								<dd>{{ selectedNode.path }}</dd>
							</div>
						</dl>
					</section>

					<data-binding-path local-path="automation">
						<section class="node-automation__context-section">
							<button type="button" class="node-automation__context-header" :aria-expanded="configOpen" @click="configOpen = !configOpen">
								<span><i class="mdi mdi-tune" /> Configure</span>
								<i :class="configOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
							</button>
							<div v-if="configOpen" class="node-automation__config">
								<action-config-edit
									v-if="selectedActionDef && !selectedActionMissing"
									v-model="selectedActionDef"
									:local-path="selectedActionPath"
								/>
								<div v-else-if="selectedActionMissing" class="node-automation__missing-schema">
									<i class="mdi mdi-alert-circle-outline" />
									<strong>Missing action schema</strong>
									<span>{{ selectedActionInfo?.plugin }} / {{ selectedActionInfo?.action }}</span>
									<small>The plugin or action was removed or renamed. The node is preserved so you can reconnect it or delete it safely.</small>
								</div>
								<div v-else-if="selectedTriggerMissing" class="node-automation__missing-schema">
									<i class="mdi mdi-alert-circle-outline" />
									<strong>Missing trigger schema</strong>
									<span>{{ model.plugin }} / {{ model.trigger }}</span>
									<small>The trigger was removed or renamed. Pick a new trigger from the context menu to repair this automation.</small>
								</div>
								<trigger-config-edit v-else-if="selectedNode.id === 'trigger'" v-model="model" />
								<div v-else-if="selectedNode.kind === 'variable' && selectedVariableNode" class="node-automation__variable-edit">
									<label>
										<span>Name</span>
										<input
											type="text"
											:value="selectedVariableNode?.name"
											placeholder="Variable name..."
											@change="updateVariableNodeName(selectedVariableNode!.id, ($event.target as HTMLInputElement).value)"
										/>
									</label>
									<label>
										<span>Value</span>
										<input
											v-if="selectedVariableNode?.type === 'string'"
											type="text"
											:value="selectedVariableNode.value"
											@change="updateVariableNodeValue(selectedVariableNode!.id, ($event.target as HTMLInputElement).value)"
										/>
										<input
											v-else-if="selectedVariableNode?.type === 'number'"
											type="number"
											:value="selectedVariableNode.value"
											step="any"
											@change="updateVariableNodeValue(selectedVariableNode!.id, Number(($event.target as HTMLInputElement).value))"
										/>
										<select
											v-else-if="selectedVariableNode?.type === 'boolean'"
											:value="String(selectedVariableNode.value)"
											@change="updateVariableNodeValue(selectedVariableNode!.id, ($event.target as HTMLSelectElement).value === 'true')"
										>
											<option value="true">true</option>
											<option value="false">false</option>
										</select>
										<input
											v-else-if="selectedVariableNode?.type === 'color'"
											type="color"
											:value="selectedVariableNode.value"
											@change="updateVariableNodeValue(selectedVariableNode!.id, ($event.target as HTMLInputElement).value)"
										/>
									</label>
								</div>
								<div v-else-if="selectedControlNode" class="node-automation__control-edit">
									<template v-if="selectedControlNode.type === 'if' || selectedControlNode.type === 'while'">
										<label>
											<span>{{ selectedControlNode.type === 'if' ? 'Condition' : 'Loop while' }}</span>
											<select
												:value="expressionMode(selectedControlNode.condition)"
												@change="setControlExpressionMode(selectedControlNode, 'condition', ($event.target as HTMLSelectElement).value)"
											>
												<option value="true">Always true</option>
												<option value="false">Always false</option>
												<option value="variable">Variable is truthy</option>
												<option value="equals">Variable equals value</option>
											</select>
										</label>
										<label v-if="expressionMode(selectedControlNode.condition) === 'variable' || expressionMode(selectedControlNode.condition) === 'equals'">
											<span>Variable</span>
											<expression-text-input
												list="node-expression-suggestions"
												:model-value="expressionVariable(selectedControlNode.condition)"
												placeholder="message.approved"
												:invalid="Boolean(expressionValidationMessage(selectedControlNode.condition))"
												@change="setControlExpressionVariable(selectedControlNode, 'condition', $event)"
											/>
										</label>
										<label v-if="expressionMode(selectedControlNode.condition) === 'equals'">
											<span>Equals</span>
											<input
												type="text"
												:value="expressionCompareValue(selectedControlNode.condition)"
												placeholder="approved"
												@change="setControlExpressionCompareValue(selectedControlNode, 'condition', ($event.target as HTMLInputElement).value)"
											/>
										</label>
										<div class="node-automation__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(selectedControlNode.condition)) }">
											<code>{{ summarizeExpression(selectedControlNode.condition) }}</code>
											<small>{{ expressionValidationMessage(selectedControlNode.condition) || "Expression looks valid" }}</small>
										</div>
										<label v-if="selectedControlNode.type === 'while'">
											<span>Max iterations</span>
											<input
												type="number"
												min="1"
												step="1"
												:value="selectedControlNode.maxIterations ?? 1000"
												@change="setControlNumber(selectedControlNode, 'maxIterations', Number(($event.target as HTMLInputElement).value))"
											/>
										</label>
									</template>
									<template v-else-if="selectedControlNode.type === 'for'">
										<label>
											<span>Counter</span>
											<input
												type="text"
												:value="selectedControlNode.variable"
												@change="setControlString(selectedControlNode, 'variable', ($event.target as HTMLInputElement).value)"
											/>
										</label>
										<label>
											<span>Start</span>
											<input
												type="number"
												:value="literalNumber(selectedControlNode.start)"
												@change="setControlLiteralNumber(selectedControlNode, 'start', Number(($event.target as HTMLInputElement).value))"
											/>
										</label>
										<label>
											<span>End</span>
											<input
												type="number"
												:value="literalNumber(selectedControlNode.end)"
												@change="setControlLiteralNumber(selectedControlNode, 'end', Number(($event.target as HTMLInputElement).value))"
											/>
										</label>
										<label>
											<span>Step</span>
											<input
												type="number"
												:value="literalNumber(selectedControlNode.step, 1)"
												@change="setControlLiteralNumber(selectedControlNode, 'step', Number(($event.target as HTMLInputElement).value))"
											/>
										</label>
									</template>
									<template v-else-if="selectedControlNode.type === 'forEach'">
										<label>
											<span>Item variable</span>
											<input
												type="text"
												:value="selectedControlNode.variable"
												@change="setControlString(selectedControlNode, 'variable', ($event.target as HTMLInputElement).value)"
											/>
										</label>
										<label>
											<span>Collection variable</span>
											<expression-text-input
												list="node-expression-suggestions"
												:model-value="expressionVariable(selectedControlNode.collection)"
												placeholder="items"
												:invalid="Boolean(expressionValidationMessage(selectedControlNode.collection))"
												@change="setControlExpressionVariable(selectedControlNode, 'collection', $event)"
											/>
										</label>
										<div class="node-automation__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(selectedControlNode.collection)) }">
											<code>{{ summarizeExpression(selectedControlNode.collection) }}</code>
											<small>{{ expressionValidationMessage(selectedControlNode.collection) || "Expression looks valid" }}</small>
										</div>
									</template>
									<template v-else-if="selectedControlNode.type === 'switch'">
										<label>
											<span>Switch variable</span>
											<expression-text-input
												list="node-expression-suggestions"
												:model-value="expressionVariable(selectedControlNode.expression)"
												placeholder="platform"
												:invalid="Boolean(expressionValidationMessage(selectedControlNode.expression))"
												@change="setControlExpressionVariable(selectedControlNode, 'expression', $event)"
											/>
										</label>
										<div class="node-automation__expression-summary" :class="{ invalid: Boolean(expressionValidationMessage(selectedControlNode.expression)) }">
											<code>{{ summarizeExpression(selectedControlNode.expression) }}</code>
											<small>{{ expressionValidationMessage(selectedControlNode.expression) || "Expression looks valid" }}</small>
										</div>
										<div class="node-automation__case-list">
											<div v-for="(item, ci) in selectedControlNode.cases" :key="item.port">
												<input
													type="text"
													:value="String(item.value)"
													placeholder="case value"
													@change="setSwitchCaseValue(selectedControlNode, ci, ($event.target as HTMLInputElement).value)"
												/>
												<button type="button" class="danger" @click="deleteSwitchCase(selectedControlNode, ci)">
													<i class="mdi mdi-trash-can-outline" />
												</button>
											</div>
											<button type="button" @click="addSwitchCase(selectedControlNode)">
												<i class="mdi mdi-plus" /> Add case
											</button>
										</div>
									</template>
									<p v-else class="node-automation__hint">This control node does not have editable fields yet.</p>
								</div>
								<p v-else class="node-automation__hint">
									This node groups other actions. Select a child action node to edit its settings.
								</p>
							</div>
						</section>
					</data-binding-path>

					<section class="node-automation__context-section">
						<button type="button" class="node-automation__context-header" :aria-expanded="actionsOpen" @click="actionsOpen = !actionsOpen">
							<span><i class="mdi mdi-dots-horizontal-circle-outline" /> Node Actions</span>
							<i :class="actionsOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
						</button>
						<div v-if="actionsOpen" class="node-automation__quick-actions">
							<div class="node-automation__action-picker">
								<label>
									<span>Add Action</span>
									<input v-model="actionPaletteQuery" type="search" placeholder="Search plugin or action..." />
									<select v-model="selectedActionToAdd">
										<option value="">Choose an action...</option>
										<optgroup v-for="plugin in actionPalette" :key="plugin.id" :label="plugin.name">
											<option v-for="action in plugin.actions" :key="action.key" :value="action.key">
												{{ action.name }}
											</option>
										</optgroup>
									</select>
								</label>
								<button type="button" :disabled="!selectedActionToAdd" @click="addActionFromPalette">
									<i class="mdi mdi-plus" />
									Insert After Selection
								</button>
								<div class="node-automation__palette-list">
									<button
										v-for="action in flatActionPalette"
										:key="action.key"
										type="button"
										draggable="true"
										@click="selectedActionToAdd = action.key"
										@dragstart="startActionPaletteDrag($event, action.key)"
									>
										<i class="mdi mdi-drag" />
										<span>{{ action.pluginName }}</span>
										<strong>{{ action.name }}</strong>
									</button>
								</div>
							</div>
							<div class="node-automation__action-grid">
								<button type="button" :disabled="!canEditSelectedAction" @click="duplicateSelectedAction">
									<i class="mdi mdi-content-duplicate" />
									Duplicate
								</button>
								<button type="button" :disabled="!canMoveSelectedAction(-1)" @click="moveSelectedAction(-1)">
									<i class="mdi mdi-arrow-left" />
									Move Left
								</button>
								<button type="button" :disabled="!canMoveSelectedAction(1)" @click="moveSelectedAction(1)">
									<i class="mdi mdi-arrow-right" />
									Move Right
								</button>
								<button type="button" class="danger" :disabled="!canEditSelectedAction" @click="deleteSelectedAction">
									<i class="mdi mdi-trash-can-outline" />
									Delete
								</button>
							</div>
							<button type="button" @click="resetSelectedNodePosition">
								<i class="mdi mdi-crosshairs-gps" />
								Reset Visual Position
							</button>
							<button type="button" :disabled="selectedNodeIds.size < 1" @click="collapseSelectionToSubgraph">
								<i class="mdi mdi-function" />
								Collapse Selection to Subgraph
							</button>
						</div>
					</section>
				</template>
				<p v-else class="node-automation__hint">
					Left click selects a node. Right click opens the context menu to add nodes.
				</p>

				<section class="node-automation__context-section">
					<button type="button" class="node-automation__context-header" :aria-expanded="subgraphsOpen" @click="subgraphsOpen = !subgraphsOpen">
						<span><i class="mdi mdi-function-variant" /> Subgraphs</span>
						<i :class="subgraphsOpen ? 'mdi mdi-chevron-up' : 'mdi mdi-chevron-down'" />
					</button>
					<div v-if="subgraphsOpen" class="node-automation__subgraphs">
						<ul v-if="subgraphsList.length" class="node-automation__subgraph-list">
							<li
								v-for="sg in subgraphsList"
								:key="sg.id"
								class="node-automation__subgraph-item"
								:class="{ focused: focusedSubgraphId === sg.id }"
							>
								<label class="node-automation__subgraph-name">
									<i class="mdi mdi-function" />
									<input
										type="text"
										:value="sg.name"
										placeholder="Subgraph name"
										@change="updateSubgraphName(sg.id, ($event.target as HTMLInputElement).value)"
									/>
								</label>
								<span class="node-automation__subgraph-meta">
									{{ sg.parameters.length }} param{{ sg.parameters.length === 1 ? '' : 's' }},
									{{ sg.outputs.length }} output{{ sg.outputs.length === 1 ? '' : 's' }},
									{{ sg.nodes.length }} node{{ sg.nodes.length === 1 ? '' : 's' }}
								</span>
								<div class="node-automation__subgraph-tools">
									<button type="button" title="Open subgraph canvas" @click="openSubgraphCanvas(sg.id)">
										<i class="mdi mdi-open-in-app" /> Open
									</button>
									<button type="button" title="Focus subgraph details" @click="focusSubgraph(sg.id)">
										<i class="mdi mdi-crosshairs-gps" /> Focus
									</button>
									<button type="button" title="Add a call node for this subgraph" @click="addSubgraphCallNode(sg.id)">
										<i class="mdi mdi-plus-box-outline" /> Call
									</button>
								</div>
								<div class="node-automation__subgraph-params">
									<strong>Inputs</strong>
									<div v-for="(param, pi) in sg.parameters" :key="`in-${sg.id}-${pi}`">
										<input :value="param.name" placeholder="name" @change="updateSubgraphParam(sg.id, 'parameters', pi, 'name', ($event.target as HTMLInputElement).value)" />
										<select :value="param.type" @change="updateSubgraphParam(sg.id, 'parameters', pi, 'type', ($event.target as HTMLSelectElement).value)">
											<option v-for="type in SUBGRAPH_PARAM_TYPES" :key="type" :value="type">{{ type }}</option>
										</select>
										<input :value="String(param.default ?? '')" placeholder="default" @change="updateSubgraphParam(sg.id, 'parameters', pi, 'default', ($event.target as HTMLInputElement).value)" />
										<button type="button" class="danger" @click="deleteSubgraphParam(sg.id, 'parameters', pi)"><i class="mdi mdi-close" /></button>
									</div>
									<button type="button" @click="addSubgraphParam(sg.id, 'parameters')"><i class="mdi mdi-plus" /> Input</button>
									<strong>Outputs</strong>
									<div v-for="(param, pi) in sg.outputs" :key="`out-${sg.id}-${pi}`">
										<input :value="param.name" placeholder="name" @change="updateSubgraphParam(sg.id, 'outputs', pi, 'name', ($event.target as HTMLInputElement).value)" />
										<select :value="param.type" @change="updateSubgraphParam(sg.id, 'outputs', pi, 'type', ($event.target as HTMLSelectElement).value)">
											<option v-for="type in SUBGRAPH_PARAM_TYPES" :key="type" :value="type">{{ type }}</option>
										</select>
										<button type="button" class="danger" @click="deleteSubgraphParam(sg.id, 'outputs', pi)"><i class="mdi mdi-close" /></button>
									</div>
									<button type="button" @click="addSubgraphParam(sg.id, 'outputs')"><i class="mdi mdi-plus" /> Output</button>
								</div>
								<button type="button" class="danger" title="Delete subgraph" @click="deleteSubgraph(sg.id)">
									<i class="mdi mdi-trash-can-outline" />
								</button>
							</li>
						</ul>
						<p v-else class="node-automation__hint">No subgraphs defined.</p>
						<button type="button" class="node-automation__add-subgraph" @click="addSubgraph">
							<i class="mdi mdi-plus" /> New Subgraph
						</button>
					</div>
				</section>

				<section v-if="activeTestExecution?.executionPath?.length" class="node-automation__context-section">
					<div class="node-automation__execution-header">
						<span><i class="mdi mdi-map-marker-path" /> Execution Path</span>
						<small>{{ activeTestExecution.running ? "Running" : "Last run" }}</small>
					</div>
					<ol class="node-automation__execution-path">
						<li v-for="(nodeId, execIdx) in activeTestExecution.executionPath" :key="`${execIdx}:${nodeId}`">
							<span>{{ nodeTitleById(nodeId) }}</span>
							<small v-if="activeTestExecution.nodeErrors[nodeId]" class="error">{{ activeTestExecution.nodeErrors[nodeId] }}</small>
							<small v-else-if="activeTestExecution.nodeDurations[nodeId] != null">{{ formatNodeDuration(activeTestExecution.nodeDurations[nodeId]) }}</small>
							<small v-else>running</small>
						</li>
					</ol>
				</section>
			</aside>
			<div aria-live="polite" class="sr-only">{{ screenReaderAnnouncement }}</div>
		</div>

	</div>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, useModel, watch } from "vue"
import { nanoid } from "nanoid"
import {
	ActionSelection,
	AutomationConfig,
	AutomationResourceView,
	ActionConfigEdit,
	DataBindingPath,
	TriggerConfigEdit,
	useCommitUndo,
	usePluginStore,
	ActionDefinition,
	useActionQueueStore,
	CollapsibleContextMenu,
} from "showrunner-ui-core"
import {
	ActionInfo,
	isObjectSchema,
	constructDefault,
	type AutomationDataWire,
	type AutomationVariableNode,
	type Expression,
	type GraphNode,
	type GraphEdge,
	type AutomationGraph,
	type GraphNodeType,
	type SubgraphParamType,
	type SubgraphDefinition,
} from "showrunner-schema"
import { useNodeCanvas, type NodeEditorViewState, type NodePosition } from "./useNodeCanvas"
import { useNodeContextMenu } from "./useNodeContextMenu"
import { useNodeDrag } from "./useNodeDrag"
import { useAutomationPreview } from "./useAutomationPreview"
import { areTypesCompatible, usePortConnections, portTypeColor, wouldCreateDataWireCycle, type DataWire, type PortDef } from "./usePortConnections"
import { useExecEdges } from "./useExecEdges"
import { useClipboard } from "./useClipboard"
import { connectFlowToNode as connectGraphFlowToNode, isTerminalControlFlowNode, resolveContextActionPosition } from "./automation-graph-editing"
import ExpressionTextInput from "./ExpressionTextInput.vue"
import { EXPRESSION_BUILTINS } from "./expression-tokenizer"
import {
	type ConfigLine,
	type NodeData,
	type EdgeData,
	type LaneData,
	NODE_WIDTH,
	NODE_BASE_HEIGHT,
	H_GAP,
	computeNodeHeight,
	GRAPH_NODE_INFO,
	summarizeExpression,
	buildGraph,
	buildGraphFromAutomationGraph,
	getNodeLane,
} from "./useNodeRendering"

const props = defineProps<{
	modelValue: AutomationConfig
	view: AutomationResourceView & {
		nodePositions?: Record<string, NodePosition>
		nodeView?: NodeEditorViewState
		nodeSizes?: Record<string, { width: number }>
	}
}>()

const model = useModel(props, "modelValue")
const view = useModel(props, "view")
const selectedNodeId = ref<string>()
const selectedNodeIds = ref<Set<string>>(new Set())
const selectedActionToAdd = ref("")
const actionPaletteQuery = ref("")
const dropTargetNodeId = ref<string>()
const dropTargetEdgeId = ref<string>()
const selectedEdgeId = ref<string>()
const spaceHeld = ref(false)
const ghostNode = ref<{ x: number; y: number } | null>(null)
const rubberBand = ref<{ x: number; y: number; width: number; height: number } | null>(null)
const canvasSearchOpen = ref(false)
const canvasSearchQuery = ref("")
const canvasSearchIndex = ref(0)
const canvasSearchInputRef = ref<HTMLInputElement>()
const contextMenuRootRef = ref<HTMLElement>()
const contextMenuFocusIndex = ref(-1)
const detailsOpen = ref(true)
const configOpen = ref(true)
const actionsOpen = ref(false)
const subgraphsOpen = ref(false)
const focusedSubgraphId = ref<string>()
const activeSubgraphId = ref<string>()
const recentlyUsed = ref<{ key: string; kind: "action" | "trigger"; name: string; icon: string; color: string }[]>([])
const pendingFlowConnection = ref<{ fromNode: string; fromPort?: string; canvasPoint: NodePosition } | null>(null)
const recentContextItems = computed(() =>
	(pendingFlowConnection.value ? recentlyUsed.value.filter((item) => item.kind === "action") : recentlyUsed.value)
		.filter((item) => isPluginEnabledForContextKey(item.key))
)
const MAX_RECENT = 5
const pluginStore = usePluginStore()
const commitUndo = useCommitUndo()
const actionQueueStore = useActionQueueStore()
const activeTestExecutionId = ref<string>()
const activeTestExecution = computed(() => {
	if (!activeTestExecutionId.value) return undefined
	return actionQueueStore.activeTestExecutions[activeTestExecutionId.value]
})
const subgraphsList = computed(() => model.value.subgraphs ?? [])
const activeSubgraph = computed(() => {
	if (!activeSubgraphId.value) return undefined
	return model.value.subgraphs?.find((subgraph) => subgraph.id === activeSubgraphId.value)
})
const isEditingSubgraph = computed(() => Boolean(activeSubgraph.value))
const activeGraph = computed<AutomationGraph | undefined>(() => activeSubgraph.value ?? model.value.graph)

const nodePositions = computed(() => {
	if (!view.value) return {}
	view.value.nodePositions ??= {}
	return view.value.nodePositions
})
const nodeSizes = computed(() => {
	if (!view.value) return {}
	view.value.nodeSizes ??= {}
	return view.value.nodeSizes!
})
const dataWires = computed({
	get: () => {
		if (!model.value) return []
		if (activeSubgraph.value) {
			activeSubgraph.value.dataWires ??= []
			return activeSubgraph.value.dataWires
		}
		model.value.dataWires ??= []
		return model.value.dataWires!
	},
	set: (v: AutomationDataWire[]) => {
		if (!model.value) return
		if (activeSubgraph.value) {
			activeSubgraph.value.dataWires = v
			return
		}
		model.value.dataWires = v
	},
})
const variableNodes = computed({
	get: () => {
		if (!model.value) return []
		model.value.variableNodes ??= []
		return model.value.variableNodes!
	},
	set: (v: AutomationVariableNode[]) => {
		if (!model.value) return
		model.value.variableNodes = v
	},
})

const CONSTANT_TYPE_INFO: Record<string, { icon: string; portType: string; color: string }> = {
	string: { icon: "mdi mdi-format-text", portType: "str", color: "#81c784" },
	number: { icon: "mdi mdi-numeric", portType: "num", color: "#4fc3f7" },
	boolean: { icon: "mdi mdi-toggle-switch-outline", portType: "bool", color: "#ffb74d" },
	color: { icon: "mdi mdi-palette", portType: "color", color: "#f06292" },
}
const SUBGRAPH_PARAM_TYPES: SubgraphParamType[] = ["string", "number", "boolean", "array", "object", "color", "any"]
type VariableNodeType = "string" | "number" | "boolean" | "color"
type ControlFlowNodeType = Exclude<GraphNodeType, "action" | "subgraphCall">
type ContextSearchResult =
	| { kind: "action" | "trigger"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string }
	| { kind: "variable"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string; variableType: VariableNodeType }
	| { kind: "control"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string; controlType: ControlFlowNodeType }
	| { kind: "subgraph"; key: string; name: string; detail: string; label: string; icon: string; color: string; searchText: string; subgraphId: string }
const CONTEXT_VARIABLE_ITEMS: Array<Omit<Extract<ContextSearchResult, { kind: "variable" }>, "searchText">> = [
	{ kind: "variable", key: "string", name: "String Variable", detail: "Data", label: "Variable", icon: "mdi mdi-format-text", color: "#81c784", variableType: "string" },
	{ kind: "variable", key: "number", name: "Number Variable", detail: "Data", label: "Variable", icon: "mdi mdi-numeric", color: "#4fc3f7", variableType: "number" },
	{ kind: "variable", key: "boolean", name: "Boolean Variable", detail: "Data", label: "Variable", icon: "mdi mdi-toggle-switch-outline", color: "#ffb74d", variableType: "boolean" },
	{ kind: "variable", key: "color", name: "Color Variable", detail: "Data", label: "Variable", icon: "mdi mdi-palette", color: "#f06292", variableType: "color" },
]
const CONTEXT_CONTROL_ITEMS: Array<Omit<Extract<ContextSearchResult, { kind: "control" }>, "searchText">> = [
	{ kind: "control", key: "if", name: "If / Else", detail: "Conditional branch", label: "Control", icon: "mdi mdi-source-branch", color: "#64b5f6", controlType: "if" },
	{ kind: "control", key: "switch", name: "Switch", detail: "Multi-way branch", label: "Control", icon: "mdi mdi-source-fork", color: "#64b5f6", controlType: "switch" },
	{ kind: "control", key: "for", name: "For Loop", detail: "Counter-based loop", label: "Control", icon: "mdi mdi-repeat", color: "#68d391", controlType: "for" },
	{ kind: "control", key: "forEach", name: "For Each", detail: "Iterate over collection", label: "Control", icon: "mdi mdi-format-list-numbered", color: "#68d391", controlType: "forEach" },
	{ kind: "control", key: "while", name: "While Loop", detail: "Condition-based loop", label: "Control", icon: "mdi mdi-sync", color: "#68d391", controlType: "while" },
	{ kind: "control", key: "break", name: "Break", detail: "Exit current loop", label: "Control", icon: "mdi mdi-debug-step-out", color: "#ef9a9a", controlType: "break" },
	{ kind: "control", key: "continue", name: "Continue", detail: "Next iteration", label: "Control", icon: "mdi mdi-skip-next", color: "#ef9a9a", controlType: "continue" },
	{ kind: "control", key: "return", name: "Return", detail: "End execution", label: "Control", icon: "mdi mdi-keyboard-return", color: "#ef9a9a", controlType: "return" },
]

const graph = computed(() => {
	if (activeSubgraph.value) {
		return buildGraphFromAutomationGraph(activeSubgraph.value, pluginStore.pluginMap, model.value.subgraphs ?? [])
	}
	return buildGraph(model.value, pluginStore.pluginMap, getPreviewConfiguredDurationSeconds)
})
const nodes = computed(() => {
	const actionNodes = graph.value.nodes.map((node) => ({
		...node,
		...(nodePositions.value[node.id] ?? { x: node.x, y: node.y }),
		width: nodeSizes.value[node.id]?.width ?? NODE_WIDTH,
	}))
	// Add variable nodes
	const varNodes: NodeData[] = variableNodes.value.map((vn) => {
		const info = CONSTANT_TYPE_INFO[vn.type] ?? CONSTANT_TYPE_INFO.string
		const pos = nodePositions.value[vn.id] ?? { x: vn.x, y: vn.y }
		const inPorts: PortDef[] = [{ key: "value", label: "set", type: info.portType }]
		const outPorts: PortDef[] = [{ key: "value", label: "value", type: info.portType }]
		return {
			id: vn.id,
			kind: "variable" as const,
			title: vn.name || vn.type.charAt(0).toUpperCase() + vn.type.slice(1),
			subtitle: String(vn.value),
			icon: info.icon,
			badge: info.portType,
			x: pos.x,
			y: pos.y,
			inputPorts: inPorts,
			outputPorts: outPorts,
			height: computeNodeHeight(undefined, inPorts, outPorts),
			width: nodeSizes.value[vn.id]?.width ?? 160,
		}
	})
	return [...actionNodes, ...varNodes]
})
const canvasSearchResults = computed(() => {
	const q = canvasSearchQuery.value.toLowerCase().trim()
	if (!q) return []
	return nodes.value.filter((n) => {
		const text = `${n.title} ${n.subtitle} ${n.kind} ${n.badge ?? ""} ${(n.configLines ?? []).map((l) => `${l.label} ${l.value}`).join(" ")}`.toLowerCase()
		return text.includes(q)
	})
})
const canvasSearchMatchIds = computed(() => new Set(canvasSearchResults.value.map((n) => n.id)))
const screenReaderAnnouncement = computed(() => {
	if (selectedNodeIds.value.size === 0) return ""
	if (selectedNodeIds.value.size === 1) {
		const node = nodes.value.find((n) => n.id === selectedNodeId.value)
		return node ? `Selected ${node.kind} node: ${node.title}` : ""
	}
	return `${selectedNodeIds.value.size} nodes selected`
})
const edges = computed<EdgeData[]>(() => {
	if (!activeGraph.value) return []
	// Build edges from the graph data, computing SVG paths
	const nodeMap = new Map(nodes.value.map((n) => [n.id, n]))
	return graph.value.edges.map((e) => {
		const fromNode = nodeMap.get(e.from)
		const toNode = nodeMap.get(e.to)
		const fromX = fromNode ? fromNode.x + (fromNode.width ?? NODE_WIDTH) : 0
		const fromY = fromNode ? fromNode.y + fromNode.height / 2 : 0
		const toX = toNode ? toNode.x : 0
		const toY = toNode ? toNode.y + toNode.height / 2 : 0
		const cpOffset = Math.min(80, Math.abs(toX - fromX) / 2)
		const path = `M${fromX},${fromY} C${fromX + cpOffset},${fromY} ${toX - cpOffset},${toY} ${toX},${toY}`
		const label = getEdgeLabel(e)
		return {
			id: e.id,
			from: e.from,
			to: e.to,
			port: e.port,
			label,
			labelWidth: getEdgeLabelWidth(label),
			labelX: (fromX + toX) / 2,
			labelY: (fromY + toY) / 2 - 10,
			path,
		}
	}).filter((e) => e.path)
})
const visibleFlowEdges = computed(() => edges.value)
const currentPreviewRouteLabel = computed(() => {
	const nodeId = currentPreviewStep.value?.node.id
	if (!nodeId || !activeGraph.value) return undefined
	const incoming = activeGraph.value.edges.find((edge) => edge.to === nodeId)
	return incoming ? getEdgeLabel(incoming) : undefined
})
const lanes = computed<LaneData[]>(() => {
	const groups = new Map<string, { kind: LaneData["kind"]; label: string; nodes: NodeData[] }>()
	for (const node of nodes.value) {
		const lane = getNodeLane(node)
		const group = groups.get(lane.id)
		if (group) {
			group.nodes.push(node)
		} else {
			groups.set(lane.id, { kind: lane.kind, label: lane.label, nodes: [node] })
		}
	}

	return [...groups.entries()].map(([id, group]) => {
		const minX = Math.min(...group.nodes.map((node) => node.x))
		const minY = Math.min(...group.nodes.map((node) => node.y))
		const maxX = Math.max(...group.nodes.map((node) => node.x + NODE_WIDTH))
		const maxY = Math.max(...group.nodes.map((node) => node.y + node.height))
		return {
			id,
			kind: group.kind,
			label: group.label,
			x: Math.max(12, minX - 18),
			y: Math.max(12, minY - 34),
			width: Math.max(NODE_WIDTH + 36, maxX - minX + 36),
			height: Math.max(NODE_BASE_HEIGHT + 58, maxY - minY + 58),
		}
	})
})
const selectedNode = computed(() => nodes.value.find((node) => node.id === selectedNodeId.value))
const selectedVariableNode = computed(() => {
	if (!selectedNodeId.value) return undefined
	return variableNodes.value.find((vn) => vn.id === selectedNodeId.value)
})
const selectedControlNode = computed(() => {
	if (!selectedNodeId.value) return undefined
	const node = activeGraph.value?.nodes.find((item) => item.id === selectedNodeId.value)
	return node && node.type !== "action" ? node : undefined
})
const previewNodes = computed(() => nodes.value.filter((node) => node.id !== "trigger").sort((a, b) => a.x - b.x || a.y - b.y))
const expressionSuggestions = computed(() => {
	const suggestions = new Set<string>()
	for (const node of variableNodes.value) {
		if (node.name) suggestions.add(node.name)
	}
	for (const port of nodes.value.find((node) => node.id === "trigger")?.outputPorts ?? []) {
		suggestions.add(port.key)
	}
	for (const node of nodes.value) {
		for (const port of node.outputPorts ?? []) {
			if (port.type !== "flow") suggestions.add(`${node.id}.${port.key}`)
		}
	}
	for (const builtin of EXPRESSION_BUILTINS) {
		suggestions.add(`${builtin}(...)`)
	}
	return [...suggestions].sort((a, b) => a.localeCompare(b))
})
const {
	playheadNodeId,
	isPreviewPlaying,
	playheadProgress,
	currentPreviewStep,
	playheadElapsedLabel,
	previewTotalLabel,
	togglePlayheadPreview,
	pausePlayheadPreview,
	resetPlayheadPreview,
	getConfiguredDurationSeconds: getPreviewConfiguredDurationSeconds,
} = useAutomationPreview(model, previewNodes)
const selectedActionInfo = computed(() => {
	if (!selectedNodeId.value || selectedNodeId.value === "trigger") return undefined
	const index = activeGraph.value?.nodes.findIndex((node) => node.id === selectedNodeId.value && node.type === "action") ?? -1
	if (index < 0) return undefined
	return activeGraph.value!.nodes[index] as Extract<GraphNode, { type: "action" }>
})
const selectedActionPath = computed(() => {
	if (!selectedActionInfo.value || !activeGraph.value) return undefined
	const index = activeGraph.value.nodes.findIndex((node) => node.id === selectedActionInfo.value?.id)
	if (index < 0) return undefined
	return activeSubgraph.value ? `subgraphs[${model.value.subgraphs?.findIndex((sg) => sg.id === activeSubgraph.value?.id) ?? 0}].nodes[${index}]` : `graph.nodes[${index}]`
})
const selectedActionDef = computed(() => {
	return selectedActionInfo.value
})
const selectedActionMissing = computed(() => {
	const action = selectedActionInfo.value
	if (!action) return false
	return !pluginStore.pluginMap.get(action.plugin)?.actions?.[action.action]
})
const selectedTriggerMissing = computed(() => {
	if (selectedNode.value?.id !== "trigger") return false
	if (!model.value.plugin || !model.value.trigger) return false
	return !pluginStore.pluginMap.get(model.value.plugin)?.triggers?.[model.value.trigger]
})
const canEditSelectedAction = computed(() => {
	return Boolean(selectedActionInfo.value)
})
const actionPalette = computed(() =>
	[...pluginStore.pluginMap.values()]
		.filter((plugin) => pluginStore.isPluginEnabled(plugin.id))
		.map((plugin) => ({
			id: plugin.id,
			name: plugin.name,
			actions: Object.values(plugin.actions)
				.filter((action) => action.type === "regular")
				.map((action) => ({
					key: `${plugin.id}:${action.id}`,
					name: action.name,
					searchText: `${plugin.name} ${plugin.id} ${action.name} ${action.id}`.toLowerCase(),
				}))
				.filter((action) => action.searchText.includes(actionPaletteSearch.value))
				.sort((a, b) => a.name.localeCompare(b.name)),
		}))
		.filter((plugin) => plugin.actions.length || plugin.name.toLowerCase().includes(actionPaletteSearch.value))
		.sort((a, b) => a.name.localeCompare(b.name))
)
const actionPaletteSearch = computed(() => actionPaletteQuery.value.trim().toLowerCase())
const flatActionPalette = computed(() =>
	actionPalette.value
		.flatMap((plugin) => plugin.actions.map((action) => ({ ...action, pluginName: plugin.name })))
		.slice(0, 24)
)
const viewBox = computed(() => {
	return `0 0 ${canvasSize.value.width} ${canvasSize.value.height}`
})
const canvasSize = computed(() => ({
	width: Math.max(1280, ...nodes.value.map((node) => node.x + NODE_WIDTH + 160)),
	height: Math.max(720, ...nodes.value.map((node) => node.y + node.height + 160)),
}))
const graphBounds = computed(() => {
	const minX = Math.min(42, ...nodes.value.map((node) => node.x))
	const minY = Math.min(88, ...nodes.value.map((node) => node.y))
	const maxX = Math.max(...nodes.value.map((node) => node.x + NODE_WIDTH))
	const maxY = Math.max(...nodes.value.map((node) => node.y + node.height))
	return { minX, minY, width: maxX - minX, height: maxY - minY }
})
const MINIMAP_PADDING = 40
const minimapViewBox = computed(() => {
	const b = graphBounds.value
	return `${b.minX - MINIMAP_PADDING} ${b.minY - MINIMAP_PADDING} ${b.width + MINIMAP_PADDING * 2} ${b.height + MINIMAP_PADDING * 2}`
})
const minimapViewport = computed(() => {
	const canvas = canvasRef.value
	if (!canvas) return { x: 0, y: 0, width: 400, height: 300 }
	const scrollLeft = canvas.scrollLeft
	const scrollTop = canvas.scrollTop
	const w = canvas.clientWidth
	const h = canvas.clientHeight
	const z = zoom.value
	const px = pan.value.x
	const py = pan.value.y
	return {
		x: (scrollLeft - px) / z,
		y: (scrollTop - py) / z,
		width: w / z,
		height: h / z,
	}
})
const {
	canvasRef,
	zoom,
	pan,
	isPanning,
	snapToGrid,
	ZOOM_STEP,
	setZoom,
	toggleSnapToGrid,
	snapCoordinate,
	zoomFromWheel,
	horizontalPan,
	fitGraph,
	resetView,
	fitSelection,
	startPan,
	getCanvasPointFromClient: getCanvasPointFromClientPosition,
} = useNodeCanvas(view, graphBounds, commitUndo)
const graphRef = computed(() => activeGraph.value)
const {
	execEdgeDrag,
	execDragWirePath,
	startExecEdgeDrag,
	deleteExecEdge,
} = useExecEdges(graphRef, nodes, canvasRef, zoom, commitUndo, openPendingFlowContext)
const {
	copySelectedNodes,
	cutSelectedNodes,
	pasteNodes,
} = useClipboard(model, graphRef, selectedNodeIds, selectedNodeId, variableNodes, dataWires, nodePositions, canvasRef, zoom, commitUndo, clearSelection)
const {
	contextMenu,
	contextMenuQuery,
	contextMenuSubtitle,
	actionContextGroups,
	actionCategoryGroups,
	conversionContextItems,
	triggerContextGroups,
	contextMenuSearchItems,
	disabledContextMenuSearchItems,
	openContextMenu,
	openContextMenuAt,
	closeContextMenu: closeContextMenuBase,
	toggleContextGroup,
	isContextGroupOpen,
} = useNodeContextMenu(nodes, pluginStore, getCanvasPointFromClient, getNodeLane)

watch(
	() => contextMenu.value.open,
	(open) => {
		if (!open) return
		contextMenuFocusIndex.value = -1
		nextTick(() => {
			contextMenuRootRef.value?.querySelector<HTMLInputElement>("input[type='search']")?.focus()
		})
	}
)

watch(contextMenuQuery, () => {
	contextMenuFocusIndex.value = -1
})

const contextMenuSearchResults = computed<ContextSearchResult[]>(() => {
	const query = contextMenuQuery.value.trim().toLowerCase()
	if (!query) return []

	const integrationItems: ContextSearchResult[] = contextMenuSearchItems.value
		.filter((item) => !pendingFlowConnection.value || item.kind === "action")
		.map((item) => ({
			kind: item.kind,
			key: item.key,
			name: item.name,
			detail: item.pluginName,
			label: item.kind === "trigger" ? "Trigger" : "Action",
			icon: item.icon,
			color: item.color,
			searchText: item.searchText,
		}))
	const variableItems: ContextSearchResult[] = pendingFlowConnection.value
		? []
		: CONTEXT_VARIABLE_ITEMS.map((item) => withContextSearchText(item))
	const controlItems: ContextSearchResult[] = CONTEXT_CONTROL_ITEMS.map((item) => withContextSearchText(item))
	const subgraphItems: ContextSearchResult[] = subgraphsList.value.map((subgraph) => withContextSearchText({
		kind: "subgraph",
		key: subgraph.id,
		name: subgraph.name || "Unnamed",
		detail: "Call subgraph",
		label: "Subgraph",
		icon: "mdi mdi-function",
		color: "#ce93d8",
		subgraphId: subgraph.id,
	}))

	return [...integrationItems, ...variableItems, ...controlItems, ...subgraphItems]
		.filter((item) => item.searchText.includes(query))
		.slice(0, 32)
})

const hiddenPluginSearchHint = computed(() => {
	const query = contextMenuQuery.value.trim()
	if (!query || contextMenuSearchResults.value.length) return ""
	const matches = disabledContextMenuSearchItems.value.filter((item) => !pendingFlowConnection.value || item.kind === "action")
	if (!matches.length) return ""
	const pluginNames = [...new Set(matches.map((item) => item.pluginName))].slice(0, 3)
	return `Matches exist in disabled plugins: ${pluginNames.join(", ")}. Turn them on in Integrations to add new nodes.`
})

function withContextSearchText<T extends Omit<ContextSearchResult, "searchText">>(item: T): T & { searchText: string } {
	return {
		...item,
		searchText: `${item.name} ${item.detail} ${item.label} ${item.key}`.toLowerCase(),
	}
}

function closeContextMenu() {
	pendingFlowConnection.value = null
	closeContextMenuBase()
}

function isPluginEnabledForContextKey(key: string) {
	const [pluginId] = key.split(":")
	return !pluginId || pluginStore.isPluginEnabled(pluginId)
}

function handleContextMenuKeydown(event: KeyboardEvent) {
	if (!contextMenu.value.open) return
	if (event.key === "Escape") {
		event.preventDefault()
		closeContextMenu()
		return
	}
	if (event.key === "ArrowDown") {
		event.preventDefault()
		moveContextMenuFocus(1)
		return
	}
	if (event.key === "ArrowUp") {
		event.preventDefault()
		moveContextMenuFocus(-1)
		return
	}
	if (event.key === "Enter") {
		event.preventDefault()
		activateContextMenuFocus()
		return
	}
	if ((event.ctrlKey || event.metaKey) && ["1", "2", "3", "4"].includes(event.key)) {
		event.preventDefault()
		openContextMenuSection(event.key)
	}
}

function moveContextMenuFocus(delta: number) {
	const buttons = getContextMenuButtons()
	if (!buttons.length) return
	const current = buttons.indexOf(document.activeElement as HTMLButtonElement)
	const start = current >= 0 ? current : contextMenuFocusIndex.value
	const fallback = delta > 0 ? 0 : buttons.length - 1
	const next = start >= 0 ? (start + delta + buttons.length) % buttons.length : fallback
	contextMenuFocusIndex.value = next
	buttons[next].focus({ preventScroll: true })
	buttons[next].scrollIntoView({ block: "nearest" })
}

function activateContextMenuFocus() {
	const buttons = getContextMenuButtons()
	if (!buttons.length) return
	const active = buttons.indexOf(document.activeElement as HTMLButtonElement)
	const index = active >= 0 ? active : Math.max(0, contextMenuFocusIndex.value)
	buttons[Math.min(index, buttons.length - 1)].click()
}

function openContextMenuSection(shortcut: string) {
	const sectionByShortcut: Record<string, string> = {
		"1": "categories",
		"2": "integrations",
		"3": "data",
		"4": "flow",
	}
	const section = sectionByShortcut[shortcut]
	if (!section) return
	if (!isContextGroupOpen(section)) toggleContextGroup(section)
	nextTick(() => {
		const sectionButton = contextMenuRootRef.value?.querySelector<HTMLButtonElement>(
			`[data-context-section="${section}"]`
		)
		sectionButton?.focus({ preventScroll: true })
	})
}

function getContextMenuButtons() {
	return Array.from(
		contextMenuRootRef.value?.querySelectorAll<HTMLButtonElement>(".node-automation__menu-items button") ?? []
	).filter((button) => !button.disabled && button.offsetParent !== null)
}

const { startDrag, resetSelectedNodePosition, alignmentGuides } = useNodeDrag(
	nodePositions,
	selectedNodeId,
	selectedNodeIds,
	zoom,
	snapCoordinate,
	closeContextMenu,
	commitUndo,
	nodes,
	NODE_WIDTH
)
const {
	wireDrag,
	dataWirePaths,
	dragWirePath,
	dragPortPreview,
	startWireDrag,
	deleteDataWire,
} = usePortConnections(nodes, dataWires, zoom, pan, canvasRef, commitUndo)
const selectedDataWireId = ref<string>()

/** Set of "nodeId:portKey:kind" strings for ports that have a wire connected */
const connectedPorts = computed(() => {
	const set = new Set<string>()
	for (const w of dataWires.value) {
		set.add(`${w.fromNode}:${w.fromPort}:out`)
		set.add(`${w.toNode}:${w.toPort}:in`)
	}
	return set
})
const invalidDataWireIssues = computed(() => {
	return dataWires.value.flatMap((wire) => {
		const source = resolveDataWirePort(wire.fromNode, wire.fromPort, "out")
		const target = resolveDataWirePort(wire.toNode, wire.toPort, "in")
		if (!source) return [{ id: wire.id, message: `Missing source port: ${nodeTitleById(wire.fromNode)}.${wire.fromPort}` }]
		if (!target) return [{ id: wire.id, message: `Missing target port: ${nodeTitleById(wire.toNode)}.${wire.toPort}` }]
		if (!areTypesCompatible(source.type, target.type)) {
			return [{ id: wire.id, message: `Incompatible data wire: ${source.type} -> ${target.type}` }]
		}
		const otherWires = dataWires.value.filter((item) => item.id !== wire.id)
		if (wouldCreateDataWireCycle(otherWires, wire.fromNode, wire.toNode)) {
			return [{ id: wire.id, message: "Data wire creates a circular dependency." }]
		}
		return []
	})
})

function isPortConnected(nodeId: string, portKey: string, kind: "in" | "out"): boolean {
	return connectedPorts.value.has(`${nodeId}:${portKey}:${kind}`)
}

function resolveDataWirePort(nodeId: string, portKey: string, kind: "in" | "out") {
	if (kind === "out" && nodeId === "trigger") {
		const node = nodes.value.find((item) => item.id === nodeId)
		return node?.outputPorts?.find((port) => port.key === portKey)
	}
	if (kind === "out" && nodeId.startsWith("__param:")) {
		const paramName = nodeId.slice("__param:".length)
		const param = activeSubgraph.value?.parameters.find((item) => item.name === paramName)
		if (param && portKey === "value") return { key: portKey, label: param.name, type: param.type } satisfies PortDef
	}
	if (kind === "in" && nodeId.startsWith("__output:")) {
		const outputName = nodeId.slice("__output:".length)
		const output = activeSubgraph.value?.outputs.find((item) => item.name === outputName)
		if (output && portKey === "value") return { key: portKey, label: output.name, type: output.type } satisfies PortDef
	}
	const node = nodes.value.find((item) => item.id === nodeId)
	const ports = kind === "in" ? node?.inputPorts : node?.outputPorts
	return ports?.find((port) => port.key === portKey)
}

function selectDataWireIssue(issue: { id: string }) {
	selectedDataWireId.value = issue.id
	selectedEdgeId.value = undefined
	selectedNodeId.value = undefined
	selectedNodeIds.value = new Set()
}

function cleanupInvalidDataWires() {
	const invalidIds = new Set(invalidDataWireIssues.value.map((issue) => issue.id))
	if (!invalidIds.size) return
	dataWires.value = dataWires.value.filter((wire) => !invalidIds.has(wire.id))
	selectedDataWireId.value = undefined
	commitUndo()
}

function dataPortDragClass(nodeId: string, portKey: string, kind: "in" | "out") {
	const preview = dragPortPreview.value
	if (!preview || preview.nodeId !== nodeId || preview.portKey !== portKey || preview.kind !== kind) return undefined
	return preview.valid ? "drag-valid" : "drag-invalid"
}

function dataPortDragTitle(nodeId: string, portKey: string, kind: "in" | "out") {
	const preview = dragPortPreview.value
	if (!preview || preview.nodeId !== nodeId || preview.portKey !== portKey || preview.kind !== kind) return undefined
	return preview.message ?? "Release to connect this data port."
}

function dataWireTitle(wire: DataWire & { validationMessage?: string }) {
	const value = getWireRuntimeValue(wire)
	const fromNode = nodeTitleById(wire.fromNode)
	const toNode = nodeTitleById(wire.toNode)
	const validation = "validationMessage" in wire && wire.validationMessage ? `\n${wire.validationMessage}` : ""
	if (value === undefined) return `${fromNode}.${wire.fromPort} -> ${toNode}.${wire.toPort}${validation}`
	return `${fromNode}.${wire.fromPort} -> ${toNode}.${wire.toPort}${validation}\nValue: ${summarizeRuntimeValue(value)}`
}

function getWireRuntimeValue(wire: DataWire) {
	const variable = variableNodes.value.find((node) => node.id === wire.fromNode)
	if (variable && wire.fromPort === "value") return variable.value

	const result = activeTestExecution.value?.nodeResults?.[wire.fromNode]
	return getRuntimePathValue(result, wire.fromPort)
}

function getRuntimePathValue(source: any, path: string) {
	if (source == null) return undefined
	const parts = String(path || "")
		.replace(/\[(\d+)\]/g, ".$1")
		.split(".")
		.map((part) => part.trim())
		.filter(Boolean)
	let cursor = source
	for (const part of parts) {
		if (cursor == null) return undefined
		cursor = cursor[part]
	}
	return cursor
}

function summarizeRuntimeValue(value: unknown) {
	if (value == null) return String(value)
	if (typeof value === "string") return value.length > 80 ? `${value.slice(0, 77)}...` : value
	if (typeof value === "number" || typeof value === "boolean") return String(value)
	try {
		const text = JSON.stringify(value)
		return text.length > 120 ? `${text.slice(0, 117)}...` : text
	} catch {
		return String(value)
	}
}

function isExecPortConnected(nodeId: string, portKey: string): boolean {
	if (!activeGraph.value) return false
	return activeGraph.value.edges.some((e) => e.from === nodeId && e.port === portKey)
}

function canStartFlowFromNode(node: NodeData) {
	return Boolean(activeGraph.value && node.id !== "trigger" && node.kind !== "variable")
}

function getEdgeLabel(edgeOrPort?: { from?: string; port?: string } | string) {
	const from = typeof edgeOrPort === "string" ? undefined : edgeOrPort?.from
	const port = typeof edgeOrPort === "string" ? edgeOrPort : edgeOrPort?.port
	if (!port) return undefined
	if (port === "then") return "then"
	if (port === "else") return "else"
	if (port === "default") return "default"
	if (port === "body") return "loop body"
	if (port === "next") return "done"
	if (port.startsWith("case:")) {
		const source = activeGraph.value?.nodes.find((node) => node.id === from && node.type === "switch")
		const match = source?.type === "switch" ? source.cases.find((item) => item.port === port) : undefined
		return match ? `case: ${String(match.value)}` : `case ${port.slice(5)}`
	}
	return port
}

function getEdgeLabelWidth(label?: string) {
	if (!label) return undefined
	return Math.max(60, Math.min(150, label.length * 8 + 24))
}

const removingWireIds = ref(new Set<string>())

function animateWireRemoval(wireId: string) {
	removingWireIds.value.add(wireId)
	setTimeout(() => {
		removingWireIds.value.delete(wireId)
		deleteDataWire(wireId)
	}, 300)
}


function selectNode(event: MouseEvent | PointerEvent, nodeId: string) {
	selectedEdgeId.value = undefined
	selectedDataWireId.value = undefined
	if (event.ctrlKey || event.metaKey) {
		const next = new Set(selectedNodeIds.value)
		if (next.has(nodeId)) {
			next.delete(nodeId)
			selectedNodeId.value = next.size > 0 ? [...next][next.size - 1] : undefined
		} else {
			next.add(nodeId)
			selectedNodeId.value = nodeId
		}
		selectedNodeIds.value = next
	} else {
		focusNode(nodeId)
	}
}

function focusNode(nodeId: string) {
	selectedNodeId.value = nodeId
	selectedNodeIds.value = new Set([nodeId])
	selectedEdgeId.value = undefined
}

function clearSelection() {
	selectedNodeId.value = undefined
	selectedNodeIds.value = new Set()
	selectedEdgeId.value = undefined
}

function clearNodeSelection() {
	selectedNodeId.value = undefined
	selectedNodeIds.value = new Set()
}

function selectFlowEdge(edgeId: string) {
	clearNodeSelection()
	selectedDataWireId.value = undefined
	selectedEdgeId.value = edgeId
}

function selectDataWire(wireId: string) {
	clearNodeSelection()
	selectedEdgeId.value = undefined
	selectedDataWireId.value = wireId
}

function openPendingFlowContext(drop: {
	fromNode: string
	fromPort?: string
	canvasPoint: NodePosition
	clientPoint: { x: number; y: number }
}) {
	pendingFlowConnection.value = {
		fromNode: drop.fromNode,
		fromPort: drop.fromPort,
		canvasPoint: drop.canvasPoint,
	}
	clearSelection()
	actionsOpen.value = true
	openContextMenuAt(drop.clientPoint.x, drop.clientPoint.y, drop.canvasPoint)
}

function openNodeContext(event: MouseEvent, node: NodeData) {
	pendingFlowConnection.value = null
	selectNode(event, node.id)
	detailsOpen.value = true
	configOpen.value = true
	actionsOpen.value = false
	openContextMenu(event, node.id)
}

function openCanvasContextMenu(event: MouseEvent) {
	const target = event.target as HTMLElement
	if (target.closest(".node-automation__canvas-controls") || target.closest(".node-automation__context-menu")) return
	const nodeElement = target.closest(".node-automation__node")
	if (nodeElement) return
	pendingFlowConnection.value = null
	clearSelection()
	openContextMenu(event)
}

function handleCanvasPointerDown(event: PointerEvent) {
	const target = event.target as HTMLElement
	if (target.closest(".node-automation__context-menu")) return
	if (contextMenu.value.open) closeContextMenu()
	if (target.closest(".node-automation__canvas-controls")) return

	const isCanvasTarget =
		target.classList.contains("node-automation__canvas") ||
		target.classList.contains("node-automation__surface") ||
		target.classList.contains("node-automation__edges")

	if (isCanvasTarget) clearSelection()
	if (event.button === 1 && isCanvasTarget) {
		event.preventDefault()
		startPan(event)
	}
	if (event.button === 0 && isCanvasTarget && spaceHeld.value) {
		event.preventDefault()
		startPan(event)
	} else if (event.button === 0 && isCanvasTarget) {
		selectedEdgeId.value = undefined
		selectedDataWireId.value = undefined
		startRubberBand(event)
	}
}

function startRubberBand(event: PointerEvent) {
	const canvas = canvasRef.value
	if (!canvas) return

	const origin = getCanvasPointFromClientPosition(event.clientX, event.clientY)
	const startX = event.clientX
	const startY = event.clientY
	let didMove = false

	canvas.setPointerCapture(event.pointerId)

	function onMove(moveEvent: PointerEvent) {
		const dx = Math.abs(moveEvent.clientX - startX)
		const dy = Math.abs(moveEvent.clientY - startY)
		if (!didMove && dx < 4 && dy < 4) return
		didMove = true

		const current = getCanvasPointFromClientPosition(moveEvent.clientX, moveEvent.clientY)
		const x = Math.min(origin.x, current.x)
		const y = Math.min(origin.y, current.y)
		const width = Math.abs(current.x - origin.x)
		const height = Math.abs(current.y - origin.y)
		rubberBand.value = { x, y, width, height }

		// Select nodes within the rectangle
		const ids = new Set<string>()
		for (const node of nodes.value) {
			const nodeRight = node.x + (node.width ?? NODE_WIDTH)
			const nodeBottom = node.y + node.height
			if (node.x < x + width && nodeRight > x && node.y < y + height && nodeBottom > y) {
				ids.add(node.id)
			}
		}
		selectedNodeIds.value = ids
		selectedNodeId.value = ids.size > 0 ? [...ids][0] : undefined
	}

	function onUp(upEvent: PointerEvent) {
		canvas.releasePointerCapture(upEvent.pointerId)
		canvas.removeEventListener("pointermove", onMove)
		canvas.removeEventListener("pointerup", onUp)
		canvas.removeEventListener("pointercancel", onUp)
		rubberBand.value = null
	}

	canvas.addEventListener("pointermove", onMove)
	canvas.addEventListener("pointerup", onUp)
	canvas.addEventListener("pointercancel", onUp)
}

function handleKeydown(event: KeyboardEvent) {
	const target = event.target as HTMLElement | null
	if (target?.closest("input, textarea, select, [contenteditable='true']")) return

	if (event.code === "Space" && !event.ctrlKey && !event.metaKey) {
		spaceHeld.value = true
	}

	if (event.key === "Escape" && contextMenu.value.open) {
		event.preventDefault()
		closeContextMenu()
		return
	}

	if (event.key === "Delete" || event.key === "Backspace") {
		const hasMultipleActionNodes = selectedNodeIds.value.size > 1 &&
			[...selectedNodeIds.value].some((id) => id !== "trigger" && activeGraph.value?.nodes.some((node) => node.id === id))
		if (canEditSelectedAction.value || hasMultipleActionNodes) {
			event.preventDefault()
			deleteSelectedAction()
		} else if (selectedNode.value?.kind === "variable") {
			event.preventDefault()
			deleteVariableNode(selectedNode.value.id)
			selectedNodeId.value = undefined
			selectedNodeIds.value = new Set()
		} else if (selectedEdgeId.value) {
			event.preventDefault()
			deleteSelectedEdge()
		} else if (selectedDataWireId.value) {
			event.preventDefault()
			animateWireRemoval(selectedDataWireId.value)
			selectedDataWireId.value = undefined
		}
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "d" && canEditSelectedAction.value) {
		event.preventDefault()
		duplicateSelectedAction()
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "c") {
		event.preventDefault()
		copySelectedNodes()
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "x") {
		event.preventDefault()
		cutSelectedNodes()
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "v") {
		event.preventDefault()
		pasteNodes()
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "a") {
		event.preventDefault()
		selectedNodeIds.value = new Set(nodes.value.map((n) => n.id))
		selectedNodeId.value = nodes.value[0]?.id
	}

	if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "f") {
		event.preventDefault()
		openCanvasSearch()
	}

	// Arrow key navigation between nodes
	if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key) && !event.ctrlKey && !event.metaKey) {
		event.preventDefault()
		navigateToAdjacentNode(event.key as "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown", event.shiftKey)
	}

	// Zoom shortcuts
	if ((event.ctrlKey || event.metaKey) && (event.key === "=" || event.key === "+")) {
		event.preventDefault()
		setZoom(zoom.value + ZOOM_STEP, true)
	}
	if ((event.ctrlKey || event.metaKey) && event.key === "-") {
		event.preventDefault()
		setZoom(zoom.value - ZOOM_STEP, true)
	}
	if ((event.ctrlKey || event.metaKey) && event.key === "0") {
		event.preventDefault()
		resetView()
	}

	if (event.key.toLowerCase() === "f" && !event.ctrlKey && !event.metaKey) {
		event.preventDefault()
		fitGraph()
	}
}

function handleKeyup(event: KeyboardEvent) {
	if (event.code === "Space") {
		spaceHeld.value = false
	}
}

function navigateToAdjacentNode(direction: "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown", extend: boolean) {
	const current = selectedNode.value ?? nodes.value[0]
	if (!current) return

	const cx = current.x + (current.width ?? NODE_WIDTH) / 2
	const cy = current.y + current.height / 2
	const candidates = nodes.value.filter((n) => n.id !== current.id)

	let best: NodeData | undefined
	let bestScore = Infinity

	for (const node of candidates) {
		const nx = node.x + (node.width ?? NODE_WIDTH) / 2
		const ny = node.y + node.height / 2
		const dx = nx - cx
		const dy = ny - cy

		let inDirection = false
		let primaryDist = 0
		let crossDist = 0

		switch (direction) {
			case "ArrowRight":
				inDirection = dx > 20
				primaryDist = dx
				crossDist = Math.abs(dy)
				break
			case "ArrowLeft":
				inDirection = dx < -20
				primaryDist = -dx
				crossDist = Math.abs(dy)
				break
			case "ArrowDown":
				inDirection = dy > 20
				primaryDist = dy
				crossDist = Math.abs(dx)
				break
			case "ArrowUp":
				inDirection = dy < -20
				primaryDist = -dy
				crossDist = Math.abs(dx)
				break
		}

		if (!inDirection) continue
		const score = primaryDist + crossDist * 2
		if (score < bestScore) {
			bestScore = score
			best = node
		}
	}

	if (!best) return

	if (extend) {
		const next = new Set(selectedNodeIds.value)
		next.add(best.id)
		selectedNodeIds.value = next
		selectedNodeId.value = best.id
	} else {
		focusNode(best.id)
	}
}

function openCanvasSearch() {
	canvasSearchOpen.value = true
	canvasSearchQuery.value = ""
	canvasSearchIndex.value = 0
	nextTick(() => canvasSearchInputRef.value?.focus())
}

function closeCanvasSearch() {
	canvasSearchOpen.value = false
	canvasSearchQuery.value = ""
	canvasSearchIndex.value = 0
}

function cycleSearchResult(direction: 1 | -1) {
	const results = canvasSearchResults.value
	if (!results.length) return
	canvasSearchIndex.value = (canvasSearchIndex.value + direction + results.length) % results.length
	const node = results[canvasSearchIndex.value]
	focusNode(node.id)
	scrollToNode(node)
}

function scrollToNode(node: NodeData) {
	const canvas = canvasRef.value
	if (!canvas) return
	const pos = nodePositions.value[node.id] ?? node
	const centerX = (pos.x + NODE_WIDTH / 2) * zoom.value + pan.value.x - canvas.clientWidth / 2
	const centerY = (pos.y + node.height / 2) * zoom.value + pan.value.y - canvas.clientHeight / 2
	canvas.scrollTo({ left: Math.max(0, centerX), top: Math.max(0, centerY), behavior: "smooth" })
}

function startMinimapNav(event: PointerEvent) {
	const svg = event.currentTarget as SVGSVGElement
	if (!svg || !canvasRef.value) return

	function navToPoint(clientX: number, clientY: number) {
		const canvas = canvasRef.value!
		const pt = svg.createSVGPoint()
		pt.x = clientX
		pt.y = clientY
		const ctm = svg.getScreenCTM()
		if (!ctm) return
		const svgPt = pt.matrixTransform(ctm.inverse())
		const z = zoom.value
		const px = pan.value.x
		const py = pan.value.y
		canvas.scrollTo({
			left: Math.max(0, svgPt.x * z + px - canvas.clientWidth / 2),
			top: Math.max(0, svgPt.y * z + py - canvas.clientHeight / 2),
		})
	}

	navToPoint(event.clientX, event.clientY)
	svg.setPointerCapture(event.pointerId)

	function onMove(e: PointerEvent) {
		navToPoint(e.clientX, e.clientY)
	}
	function onUp(e: PointerEvent) {
		svg.releasePointerCapture(e.pointerId)
		svg.removeEventListener("pointermove", onMove)
		svg.removeEventListener("pointerup", onUp)
		svg.removeEventListener("pointercancel", onUp)
	}
	svg.addEventListener("pointermove", onMove)
	svg.addEventListener("pointerup", onUp)
	svg.addEventListener("pointercancel", onUp)
}

watch(canvasSearchQuery, () => {
	canvasSearchIndex.value = 0
	if (canvasSearchResults.value.length) {
		const node = canvasSearchResults.value[0]
		focusNode(node.id)
		scrollToNode(node)
	}
})

function autoLayout() {
	commitUndo()
	const graphNodes = graph.value.nodes
	const positions = { ...nodePositions.value }
	for (const node of graphNodes) {
		positions[node.id] = { x: node.x, y: node.y }
	}
	view.value = { ...view.value, nodePositions: positions }
}

function fitToSelection() {
	const selected = nodes.value.filter((n) => selectedNodeIds.value.has(n.id))
	if (!selected.length) return
	const minX = Math.min(...selected.map((n) => n.x))
	const minY = Math.min(...selected.map((n) => n.y))
	const maxX = Math.max(...selected.map((n) => n.x + NODE_WIDTH))
	const maxY = Math.max(...selected.map((n) => n.y + n.height))
	fitSelection({ minX, minY, width: maxX - minX, height: maxY - minY })
}

function alignSelectedNodes(axis: "horizontal" | "vertical") {
	if (selectedNodeIds.value.size < 2) return
	commitUndo()
	const selected = nodes.value.filter((n) => selectedNodeIds.value.has(n.id))
	const positions = { ...nodePositions.value }

	if (axis === "horizontal") {
		// Align all selected to the average Y
		const avgY = selected.reduce((sum, n) => sum + n.y + n.height / 2, 0) / selected.length
		for (const node of selected) {
			positions[node.id] = { x: (positions[node.id] ?? node).x, y: avgY - node.height / 2 }
		}
	} else {
		// Align all selected to the average X
		const avgX = selected.reduce((sum, n) => sum + n.x + NODE_WIDTH / 2, 0) / selected.length
		for (const node of selected) {
			positions[node.id] = { x: avgX - NODE_WIDTH / 2, y: (positions[node.id] ?? node).y }
		}
	}
	view.value = { ...view.value, nodePositions: positions }
}

function distributeSelectedNodes() {
	if (selectedNodeIds.value.size < 3) return
	commitUndo()
	const selected = nodes.value.filter((n) => selectedNodeIds.value.has(n.id))
	const positions = { ...nodePositions.value }

	// Determine if nodes are more horizontal or vertical
	const xs = selected.map((n) => n.x)
	const ys = selected.map((n) => n.y)
	const xRange = Math.max(...xs) - Math.min(...xs)
	const yRange = Math.max(...ys) - Math.min(...ys)

	if (xRange >= yRange) {
		// Distribute horizontally
		const sorted = [...selected].sort((a, b) => a.x - b.x)
		const minX = sorted[0].x
		const maxX = sorted[sorted.length - 1].x
		const step = (maxX - minX) / (sorted.length - 1)
		for (let i = 0; i < sorted.length; i++) {
			positions[sorted[i].id] = { x: minX + step * i, y: (positions[sorted[i].id] ?? sorted[i]).y }
		}
	} else {
		// Distribute vertically
		const sorted = [...selected].sort((a, b) => a.y - b.y)
		const minY = sorted[0].y
		const maxY = sorted[sorted.length - 1].y
		const step = (maxY - minY) / (sorted.length - 1)
		for (let i = 0; i < sorted.length; i++) {
			positions[sorted[i].id] = { x: (positions[sorted[i].id] ?? sorted[i]).x, y: minY + step * i }
		}
	}
	view.value = { ...view.value, nodePositions: positions }
}

function handleWindowClick(event: MouseEvent) {
	const target = event.target as HTMLElement | null
	if (target?.closest(".node-automation__context-menu")) return
	if (contextMenu.value.open) closeContextMenu()
}

function parseActionSelection(value: string): ActionSelection | undefined {
	const [plugin, action] = value.split(":")
	if (!plugin || !action) return undefined
	return { plugin, action }
}

let dropInProgress = false

async function addActionFromPalette() {
	if (dropInProgress) return
	dropInProgress = true
	try {
	const selection = parseActionSelection(selectedActionToAdd.value)
	if (!selection) return

	const action = await pluginStore.createAction(selection)
	if (!action) return

	insertAction(action)

	focusNode(action.id)
	configOpen.value = true
	commitUndo()
	} finally { dropInProgress = false }
}

function trackRecentlyUsed(key: string, kind: "action" | "trigger", name: string, icon: string, color: string) {
	recentlyUsed.value = [{ key, kind, name, icon, color }, ...recentlyUsed.value.filter((r) => r.key !== key)].slice(0, MAX_RECENT)
}

async function selectActionFromContext(actionKey: string) {
	if (dropInProgress) return
	dropInProgress = true
	try {
	const selection = parseActionSelection(actionKey)
	if (!selection) return

	const action = await pluginStore.createAction(selection)
	if (!action) return

	const plugin = pluginStore.pluginMap.get(selection.plugin)
	const actionDef = plugin?.actions?.[selection.action]
	trackRecentlyUsed(actionKey, "action", actionDef?.name ?? selection.action, actionDef?.icon ?? "mdi mdi-play", String(plugin?.color ?? "#e9aaff"))

	const pendingFlow = pendingFlowConnection.value
	const position = resolveContextActionPosition(pendingFlow, contextMenu.value)
	insertAction(action, pendingFlow?.fromNode ?? contextMenu.value.nodeId, position, pendingFlow?.fromPort)
	if (position) nodePositions.value[action.id] = position
	focusNode(action.id)
	configOpen.value = true
	closeContextMenu()
	commitUndo()
	} finally { dropInProgress = false }
}

async function selectTriggerFromContext(triggerKey: string) {
	const [pluginId, triggerId] = triggerKey.split(":")
	const plugin = pluginStore.pluginMap.get(pluginId)
	const trigger = plugin?.triggers?.[triggerId]
	if (!pluginId || !triggerId || !trigger) return

	trackRecentlyUsed(triggerKey, "trigger", trigger.name ?? triggerId, trigger.icon ?? "mdi mdi-flash", String(plugin?.color ?? "#e9aaff"))

	const nextConfig = await constructDefault(trigger.config)
	const contextSchema = typeof trigger.context === "function" ? await trigger.context(nextConfig) : trigger.context

	Object.assign(model.value, {
		plugin: pluginId,
		trigger: triggerId,
		config: nextConfig,
		stop: model.value.stop ?? false,
		testContext: contextSchema ? await constructDefault(contextSchema) : model.value.testContext,
	})

	focusNode("trigger")
	configOpen.value = true
	closeContextMenu()
	commitUndo()
}

async function selectContextSearchResult(item: ContextSearchResult) {
	switch (item.kind) {
		case "action":
			await selectActionFromContext(item.key)
			break
		case "trigger":
			await selectTriggerFromContext(item.key)
			break
		case "variable":
			addVariableNode(item.variableType)
			break
		case "control":
			addControlFlowNode(item.controlType)
			break
		case "subgraph":
			addSubgraphCallNode(item.subgraphId)
			break
	}
}

function startActionPaletteDrag(event: DragEvent, actionKey: string) {
	event.dataTransfer?.setData("application/showrunner-action", actionKey)
	event.dataTransfer?.setData("text/plain", actionKey)
	if (event.dataTransfer) event.dataTransfer.effectAllowed = "copy"
}

async function dropActionOnCanvas(event: DragEvent) {
	if (dropInProgress) return
	dropInProgress = true
	try {
	const action = await createDraggedAction(event)
	if (!action) return

	const position = getCanvasPoint(event)
	addGraphActionNode(action, position)
	nodePositions.value[action.id] = position
	focusNode(action.id)
	configOpen.value = true
	dropTargetNodeId.value = undefined
	ghostNode.value = null
	commitUndo()
	} finally { dropInProgress = false }
}

async function dropActionOnNode(event: DragEvent, node: NodeData) {
	if (dropInProgress) return
	dropInProgress = true
	try {
	const action = await createDraggedAction(event)
	if (!action) return

	const position = {
		x: snapCoordinate(node.x + H_GAP),
		y: snapCoordinate(node.y),
	}
	insertAction(action, node.id, position)
	nodePositions.value[action.id] = position
	focusNode(action.id)
	configOpen.value = true
	dropTargetNodeId.value = undefined
	commitUndo()
	} finally { dropInProgress = false }
}

async function dropActionOnEdge(event: DragEvent, edge: EdgeData) {
	if (dropInProgress) return
	dropInProgress = true
	try {
	const action = await createDraggedAction(event)
	if (!action) return

	const fromNode = nodes.value.find((node) => node.id === edge.from)
	const toNode = nodes.value.find((node) => node.id === edge.to)
	const position = {
		x: snapCoordinate(((fromNode?.x ?? 42) + (toNode?.x ?? 42)) / 2),
		y: snapCoordinate(((fromNode?.y ?? 88) + (toNode?.y ?? 88)) / 2),
	}
	insertActionOnEdge(action, edge, position)
	nodePositions.value[action.id] = position
	focusNode(action.id)
	configOpen.value = true
	dropTargetEdgeId.value = undefined
	commitUndo()
	} finally { dropInProgress = false }
}

function clearDropTarget(nodeId: string) {
	if (dropTargetNodeId.value === nodeId) dropTargetNodeId.value = undefined
}

function clearDropEdge(edgeId: string) {
	if (dropTargetEdgeId.value === edgeId) dropTargetEdgeId.value = undefined
}

async function createDraggedAction(event: DragEvent) {
	const actionKey =
		event.dataTransfer?.getData("application/showrunner-action") || event.dataTransfer?.getData("text/plain")
	const selection = parseActionSelection(actionKey || "")
	if (!selection) return undefined
	return pluginStore.createAction(selection)
}

function ensureGraph() {
	if (activeSubgraph.value) return activeSubgraph.value
	model.value.graph ??= { nodes: [], edges: [], entryNodeId: "" }
	return model.value.graph
}

function toGraphActionNode(action: ActionInfo, position: NodePosition): Extract<GraphNode, { type: "action" }> {
	return {
		id: action.id,
		type: "action",
		plugin: action.plugin,
		action: action.action,
		config: structuredClone(action.config ?? {}),
		resultMapping: action.resultMapping ? structuredClone(action.resultMapping) : undefined,
		x: position.x,
		y: position.y,
	}
}

function addGraphActionNode(action: ActionInfo, position: NodePosition) {
	const graph = ensureGraph()
	const node = toGraphActionNode(action, position)
	graph.nodes.push(node)
	if (!graph.entryNodeId) graph.entryNodeId = node.id
	return node
}

function connectFlowToNode(fromNode: string, fromPort: string | undefined, toNode: string, isTerminal = false) {
	connectGraphFlowToNode(ensureGraph(), fromNode, fromPort, toNode, isTerminal)
}

function insertAction(action: ActionInfo, afterNodeId = selectedNodeId.value, position?: NodePosition, afterPort?: string) {
	const graph = ensureGraph()
	const canAnchorFlow = afterNodeId === "trigger" || Boolean(afterNodeId && graph.nodes.some((node) => node.id === afterNodeId))
	const flowAnchorId = canAnchorFlow ? afterNodeId : undefined
	const anchor = flowAnchorId && flowAnchorId !== "trigger" ? nodes.value.find((node) => node.id === flowAnchorId) : undefined
	const fallbackPosition = position ?? {
		x: snapCoordinate((anchor?.x ?? 42) + H_GAP),
		y: snapCoordinate(anchor?.y ?? 88),
	}
	const node = addGraphActionNode(action, fallbackPosition)

	if (!flowAnchorId) return node

	if (flowAnchorId === "trigger") {
		const previousEntry = graph.entryNodeId && graph.entryNodeId !== node.id ? graph.entryNodeId : ""
		graph.entryNodeId = node.id
		if (previousEntry) {
			graph.edges.push({ id: `${node.id}:${previousEntry}`, from: node.id, to: previousEntry })
		}
		return node
	}

	connectFlowToNode(flowAnchorId, afterPort, node.id)
	return node
}

function insertActionOnEdge(action: ActionInfo, edge: EdgeData, position: NodePosition) {
	const graph = ensureGraph()
	const node = addGraphActionNode(action, position)

	if (edge.from === "trigger") {
		const previousEntry = graph.entryNodeId && graph.entryNodeId !== node.id ? graph.entryNodeId : edge.to
		graph.entryNodeId = node.id
		if (previousEntry && previousEntry !== node.id) {
			graph.edges.push({ id: `${node.id}:${previousEntry}`, from: node.id, to: previousEntry })
		}
		return node
	}

	const existing = graph.edges.find((graphEdge) => graphEdge.id === edge.id)
	if (existing) {
		const previousTo = existing.to
		existing.to = node.id
		graph.edges.push({ id: `${node.id}:${previousTo}`, from: node.id, to: previousTo })
	} else {
		graph.edges.push({ id: `${edge.from}:${node.id}`, from: edge.from, to: node.id, port: edge.port })
		graph.edges.push({ id: `${node.id}:${edge.to}`, from: node.id, to: edge.to })
	}
	return node
}

function duplicateSelectedAction() {
	const actionInfo = selectedActionInfo.value
	if (!actionInfo) return

	const clonedAction: ActionInfo = {
		id: nanoid(),
		plugin: actionInfo.plugin,
		action: actionInfo.action,
		config: structuredClone(actionInfo.config ?? {}),
		resultMapping: actionInfo.resultMapping ? structuredClone(actionInfo.resultMapping) : undefined,
	}
	const sourceNode = selectedNode.value
	const position = {
		x: snapCoordinate((sourceNode?.x ?? actionInfo.x) + H_GAP),
		y: snapCoordinate(sourceNode?.y ?? actionInfo.y),
	}
	insertAction(clonedAction, actionInfo.id, position)
	nodePositions.value[clonedAction.id] = position
	focusNode(clonedAction.id)
	configOpen.value = true
	commitUndo()
}

function deleteSelectedAction() {
	// Multi-select: delete all selected action/variable nodes
	const idsToDelete = selectedNodeIds.value.size > 1
		? [...selectedNodeIds.value].filter((id) => id !== "trigger")
		: selectedActionInfo.value ? [selectedNodeId.value!] : []

	if (idsToDelete.length > 0) {
		// Also remove variable nodes that are in the selection
		const varIds = idsToDelete.filter((id) => variableNodes.value.some((vn) => vn.id === id))
		if (varIds.length) {
			variableNodes.value = variableNodes.value.filter((vn) => !varIds.includes(vn.id))
			dataWires.value = dataWires.value.filter((w) => !varIds.includes(w.fromNode) && !varIds.includes(w.toNode))
		}
		deleteGraphNodes(idsToDelete.filter((id) => !varIds.includes(id)))
		if (varIds.length && !idsToDelete.filter((id) => !varIds.includes(id)).length) {
			clearSelection()
			commitUndo()
		}
		return
	}
}

function deleteGraphNodes(ids: string[]) {
	const graph = activeGraph.value
	if (!graph) return
	const idSet = new Set(ids)
	graph.nodes = graph.nodes.filter((n) => !idSet.has(n.id))
	graph.edges = graph.edges.filter((e) => !idSet.has(e.from) && !idSet.has(e.to))
	// Clean data wires too
	dataWires.value = dataWires.value.filter((w) => !idSet.has(w.fromNode) && !idSet.has(w.toNode))
	// Fix entry node if deleted
	if (graph.entryNodeId && idSet.has(graph.entryNodeId)) {
		graph.entryNodeId = graph.nodes[0]?.id ?? ""
	}
	clearSelection()
	commitUndo()
}

function deleteSelectedEdge() {
	const edgeId = selectedEdgeId.value
	if (!edgeId) return
	const edge = edges.value.find((e) => e.id === edgeId)
	if (!edge) return

	if (activeGraph.value) {
		deleteExecEdge(edgeId)
		selectedEdgeId.value = undefined
		return
	}
	selectedEdgeId.value = undefined
}

function canMoveSelectedAction(direction: -1 | 1) {
	return Boolean(selectedActionInfo.value && direction)
}

function moveSelectedAction(direction: -1 | 1) {
	const nodeId = selectedActionInfo.value?.id
	if (!nodeId || !canMoveSelectedAction(direction)) return
	const node = activeGraph.value?.nodes.find((graphNode) => graphNode.id === nodeId)
	if (!node) return
	node.x = snapCoordinate(node.x + direction * H_GAP)
	nodePositions.value[node.id] = { x: node.x, y: node.y }
	commitUndo()
}

function getCanvasPoint(event: DragEvent): NodePosition {
	return getCanvasPointFromClient(event.clientX, event.clientY)
}

function updateGhostNode(event: DragEvent) {
	ghostNode.value = getCanvasPoint(event)
}

function getCanvasPointFromClient(clientX: number, clientY: number): NodePosition {
	return getCanvasPointFromClientPosition(clientX, clientY)
}

// ─── Subgraph Management ──────────────────────────────────────────────────────

function findSubgraph(id: string) {
	return model.value.subgraphs?.find((subgraph) => subgraph.id === id)
}

function addSubgraph() {
	if (!model.value.subgraphs) model.value.subgraphs = []
	const id = nanoid()
	model.value.subgraphs.push({
		id,
		name: `Subgraph ${model.value.subgraphs.length + 1}`,
		parameters: [],
		outputs: [],
		nodes: [],
		edges: [],
		dataWires: [],
		entryNodeId: "",
	})
	focusedSubgraphId.value = id
	subgraphsOpen.value = true
	commitUndo()
}

function focusSubgraph(id: string) {
	const subgraph = findSubgraph(id)
	if (!subgraph) return
	focusedSubgraphId.value = id
	subgraphsOpen.value = true
}

function openSubgraphCanvas(id: string) {
	const subgraph = findSubgraph(id)
	if (!subgraph) return
	focusedSubgraphId.value = id
	activeSubgraphId.value = id
	subgraph.dataWires ??= []
	clearSelection()
	closeContextMenu()
	subgraphsOpen.value = true
}

function openMainCanvas() {
	activeSubgraphId.value = undefined
	clearSelection()
}

function deleteSubgraph(id: string) {
	if (!model.value.subgraphs) return
	const idx = model.value.subgraphs.findIndex((s) => s.id === id)
	if (idx >= 0) {
		model.value.subgraphs.splice(idx, 1)
		// Also remove any subgraphCall nodes referencing this subgraph
		if (model.value.graph) {
			model.value.graph.nodes = model.value.graph.nodes.filter(
				(n) => !(n.type === "subgraphCall" && n.subgraphId === id)
			)
		}
		for (const subgraph of model.value.subgraphs ?? []) {
			subgraph.nodes = subgraph.nodes.filter((n) => !(n.type === "subgraphCall" && n.subgraphId === id))
		}
		if (focusedSubgraphId.value === id) focusedSubgraphId.value = undefined
		if (activeSubgraphId.value === id) activeSubgraphId.value = undefined
		commitUndo()
	}
}

function updateSubgraphName(id: string, name: string) {
	const subgraph = findSubgraph(id)
	if (!subgraph) return
	subgraph.name = name.trim() || "Unnamed Subgraph"
	commitUndo()
}

function addSubgraphParam(id: string, collection: "parameters" | "outputs") {
	const subgraph = findSubgraph(id)
	if (!subgraph) return
	const prefix = collection === "parameters" ? "input" : "output"
	subgraph[collection].push({
		name: `${prefix}${subgraph[collection].length + 1}`,
		type: "string",
		default: collection === "parameters" ? "" : undefined,
	})
	focusedSubgraphId.value = id
	commitUndo()
}

function deleteSubgraphParam(id: string, collection: "parameters" | "outputs", index: number) {
	const subgraph = findSubgraph(id)
	if (!subgraph) return
	subgraph[collection].splice(index, 1)
	focusedSubgraphId.value = id
	commitUndo()
}

function updateSubgraphParam(
	id: string,
	collection: "parameters" | "outputs",
	index: number,
	field: "name" | "type" | "default",
	value: string
) {
	const subgraph = findSubgraph(id)
	const param = subgraph?.[collection][index]
	if (!subgraph || !param) return
	if (field === "name") {
		param.name = value.trim() || `${collection === "parameters" ? "input" : "output"}${index + 1}`
	} else if (field === "type") {
		param.type = SUBGRAPH_PARAM_TYPES.includes(value as SubgraphParamType) ? value as SubgraphParamType : "any"
		if (collection === "parameters") param.default = coerceSubgraphDefault(param.type, param.default)
	} else if (collection === "parameters") {
		param.default = coerceSubgraphDefault(param.type, value)
	}
	focusedSubgraphId.value = id
	commitUndo()
}

function coerceSubgraphDefault(type: SubgraphParamType, value: unknown) {
	if (type === "number") {
		const numberValue = Number(value)
		return Number.isFinite(numberValue) ? numberValue : 0
	}
	if (type === "boolean") return value === true || String(value).toLowerCase() === "true"
	if (type === "array") {
		if (Array.isArray(value)) return value
		try {
			const parsed = JSON.parse(String(value || "[]"))
			return Array.isArray(parsed) ? parsed : []
		} catch {
			return []
		}
	}
	if (type === "object") {
		if (value && typeof value === "object" && !Array.isArray(value)) return value
		try {
			const parsed = JSON.parse(String(value || "{}"))
			return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
		} catch {
			return {}
		}
	}
	return value == null ? "" : String(value)
}

function addSubgraphCallNode(subgraphId: string) {
	const graph = ensureGraph()
	const canvasPoint = contextMenu.value.canvasPoint ?? { x: 100, y: 200 }
	const id = nanoid()
	graph.nodes.push({
		id,
		type: "subgraphCall",
		x: canvasPoint.x,
		y: canvasPoint.y,
		subgraphId,
		inputs: {},
	})
	if (pendingFlowConnection.value) {
		connectFlowToNode(pendingFlowConnection.value.fromNode, pendingFlowConnection.value.fromPort, id)
	} else if (!graph.entryNodeId) {
		graph.entryNodeId = id
	}
	focusedSubgraphId.value = subgraphId
	closeContextMenu()
	commitUndo()
}

function openSubgraphFromNode(nodeId: string) {
	const graphNode = activeGraph.value?.nodes.find((node) => node.id === nodeId)
	if (graphNode?.type !== "subgraphCall") return
	openSubgraphCanvas(graphNode.subgraphId)
}

function sanitizeSubgraphPortName(value: string, fallback: string) {
	const cleaned = String(value || "")
		.replace(/\[(\d+)\]/g, "_$1")
		.replace(/[^a-zA-Z0-9_]/g, "_")
		.replace(/^_+|_+$/g, "")
	return cleaned || fallback
}

function uniqueSubgraphPortName(base: string, used: Set<string>) {
	let candidate = sanitizeSubgraphPortName(base, "port")
	let index = 2
	while (used.has(candidate)) {
		candidate = `${sanitizeSubgraphPortName(base, "port")}${index}`
		index += 1
	}
	used.add(candidate)
	return candidate
}

function portTypeToSubgraphType(type: string | undefined): SubgraphParamType {
	switch (String(type || "any").toLowerCase()) {
		case "str":
		case "string":
			return "string"
		case "num":
		case "number":
			return "number"
		case "bool":
		case "boolean":
			return "boolean"
		case "list":
		case "array":
			return "array"
		case "obj":
		case "object":
			return "object"
		case "color":
			return "color"
		default:
			return "any"
	}
}

function getPortType(nodeId: string, portKey: string, kind: "in" | "out") {
	const node = nodes.value.find((item) => item.id === nodeId)
	const ports = kind === "in" ? node?.inputPorts : node?.outputPorts
	return ports?.find((port) => port.key === portKey)?.type
}

function collapseSelectionToSubgraph() {
	const graph = activeGraph.value
	if (!graph) return
	const selectedGraphIds = new Set(
		[...selectedNodeIds.value].filter((id) => id !== "trigger" && graph.nodes.some((node) => node.id === id))
	)
	if (selectedGraphIds.size === 0) {
		return
	}

	if (!model.value.subgraphs) model.value.subgraphs = []
	commitUndo()

	const selectedNodes = graph.nodes.filter((node) => selectedGraphIds.has(node.id))
	const internalEdges = graph.edges.filter((edge) => selectedGraphIds.has(edge.from) && selectedGraphIds.has(edge.to))
	const incomingEdges = graph.edges.filter((edge) => !selectedGraphIds.has(edge.from) && selectedGraphIds.has(edge.to))
	const outgoingEdges = graph.edges.filter((edge) => selectedGraphIds.has(edge.from) && !selectedGraphIds.has(edge.to))
	const internalDataWires = dataWires.value.filter((wire) => selectedGraphIds.has(wire.fromNode) && selectedGraphIds.has(wire.toNode))
	const incomingDataWires = dataWires.value.filter((wire) => !selectedGraphIds.has(wire.fromNode) && selectedGraphIds.has(wire.toNode))
	const outgoingDataWires = dataWires.value.filter((wire) => selectedGraphIds.has(wire.fromNode) && !selectedGraphIds.has(wire.toNode))
	const entryNodeId = selectedGraphIds.has(graph.entryNodeId)
		? graph.entryNodeId
		: selectedNodes.find((node) => !internalEdges.some((edge) => edge.to === node.id))?.id ?? selectedNodes[0]?.id ?? ""
	const x = Math.round(selectedNodes.reduce((sum, node) => sum + (node.x ?? 0), 0) / selectedNodes.length)
	const y = Math.round(selectedNodes.reduce((sum, node) => sum + (node.y ?? 0), 0) / selectedNodes.length)
	const subgraphId = nanoid()
	const callNodeId = nanoid()
	const usedInputNames = new Set<string>()
	const usedOutputNames = new Set<string>()
	const generatedInputs = incomingDataWires.map((wire) => {
		const name = uniqueSubgraphPortName(wire.toPort, usedInputNames)
		const type = portTypeToSubgraphType(getPortType(wire.toNode, wire.toPort, "in"))
		return { wire, name, type }
	})
	const generatedOutputs = outgoingDataWires.map((wire) => {
		const name = uniqueSubgraphPortName(wire.fromPort, usedOutputNames)
		const type = portTypeToSubgraphType(getPortType(wire.fromNode, wire.fromPort, "out"))
		return { wire, name, type }
	})
	const generatedInputWires: AutomationDataWire[] = generatedInputs.map(({ wire, name }) => ({
		id: `${subgraphId}:param:${name}->${wire.toNode}:${wire.toPort}`,
		fromNode: `__param:${name}`,
		fromPort: "value",
		toNode: wire.toNode,
		toPort: wire.toPort,
	}))
	const callNodeInputs = Object.fromEntries(
		generatedInputs.map(({ name }) => [name, { type: "variable", name } satisfies Expression])
	)

	model.value.subgraphs.push({
		id: subgraphId,
		name: `Subgraph ${model.value.subgraphs.length + 1}`,
		parameters: generatedInputs.map(({ name, type }) => ({ name, type, default: coerceSubgraphDefault(type, undefined) })),
		outputs: generatedOutputs.map(({ wire, name, type }) => ({
			name,
			type,
			expression: { type: "port", nodeId: wire.fromNode, port: wire.fromPort },
		})),
		nodes: structuredClone(selectedNodes),
		edges: structuredClone(internalEdges),
		dataWires: [...structuredClone(internalDataWires), ...generatedInputWires],
		entryNodeId,
	})

	graph.nodes = [
		...graph.nodes.filter((node) => !selectedGraphIds.has(node.id)),
		{ id: callNodeId, type: "subgraphCall", x, y, subgraphId, inputs: callNodeInputs },
	]
	graph.edges = graph.edges.filter((edge) => !selectedGraphIds.has(edge.from) && !selectedGraphIds.has(edge.to))
	for (const edge of incomingEdges) {
		graph.edges.push({ id: `${edge.from}:${callNodeId}:${edge.port ?? "out"}`, from: edge.from, to: callNodeId, port: edge.port })
	}
	const firstOutgoing = outgoingEdges[0]
	if (firstOutgoing) {
		graph.edges.push({ id: `${callNodeId}:${firstOutgoing.to}`, from: callNodeId, to: firstOutgoing.to })
	}
	if (selectedGraphIds.has(graph.entryNodeId)) graph.entryNodeId = callNodeId
	dataWires.value = [
		...dataWires.value.filter((wire) => !selectedGraphIds.has(wire.fromNode) && !selectedGraphIds.has(wire.toNode)),
		...generatedInputs.map(({ wire, name }) => ({
			id: `${wire.fromNode}:${wire.fromPort}->${callNodeId}:${name}`,
			fromNode: wire.fromNode,
			fromPort: wire.fromPort,
			toNode: callNodeId,
			toPort: name,
		})),
		...generatedOutputs.map(({ wire, name }) => ({
			id: `${callNodeId}:${name}->${wire.toNode}:${wire.toPort}`,
			fromNode: callNodeId,
			fromPort: name,
			toNode: wire.toNode,
			toPort: wire.toPort,
		})),
	]
	focusedSubgraphId.value = subgraphId
	subgraphsOpen.value = true
	focusNode(callNodeId)
}

function addControlFlowNode(type: GraphNodeType) {
	const canvasPoint = contextMenu.value.canvasPoint ?? { x: 100, y: 200 }
	const id = nanoid()

	// Ensure graph exists on the automation
	const graph = ensureGraph()

	let newNode: GraphNode
	switch (type) {
		case "if":
			newNode = { id, type: "if", x: canvasPoint.x, y: canvasPoint.y, condition: { type: "literal", value: true } }
			break
		case "switch":
			newNode = { id, type: "switch", x: canvasPoint.x, y: canvasPoint.y, expression: { type: "literal", value: "" }, cases: [{ value: "case1", port: "case:0" }] }
			break
		case "for":
			newNode = { id, type: "for", x: canvasPoint.x, y: canvasPoint.y, variable: "i", start: { type: "literal", value: 0 }, end: { type: "literal", value: 10 }, step: { type: "literal", value: 1 } }
			break
		case "forEach":
			newNode = { id, type: "forEach", x: canvasPoint.x, y: canvasPoint.y, variable: "item", collection: { type: "literal", value: [] } }
			break
		case "while":
			newNode = { id, type: "while", x: canvasPoint.x, y: canvasPoint.y, condition: { type: "literal", value: true }, maxIterations: 1000 }
			break
		case "break":
			newNode = { id, type: "break", x: canvasPoint.x, y: canvasPoint.y }
			break
		case "continue":
			newNode = { id, type: "continue", x: canvasPoint.x, y: canvasPoint.y }
			break
		case "return":
			newNode = { id, type: "return", x: canvasPoint.x, y: canvasPoint.y }
			break
		default:
			return
	}

	graph.nodes.push(newNode)

	if (pendingFlowConnection.value) {
		connectFlowToNode(pendingFlowConnection.value.fromNode, pendingFlowConnection.value.fromPort, id, isTerminalControlFlowNode(type))
	} else if (graph.nodes.length === 1) {
		graph.entryNodeId = id
	}

	closeContextMenu()
	commitUndo()
}

async function runMainExecution() {
	activeTestExecutionId.value = await actionQueueStore.testExecution(model.value)
}

function formatNodeDuration(durationMs: number) {
	if (durationMs < 1000) return `${Math.max(1, Math.round(durationMs))}ms`
	return `${(durationMs / 1000).toFixed(durationMs < 10000 ? 1 : 0)}s`
}

function nodeTitleById(nodeId: string) {
	return nodes.value.find((node) => node.id === nodeId)?.title ?? nodeId
}

function expressionMode(expr: Expression | undefined) {
	if (!expr) return "true"
	if (expr.type === "literal" && expr.value === false) return "false"
	if (expr.type === "literal") return "true"
	if (expr.type === "binary" && expr.op === "==" && expr.left.type === "variable") return "equals"
	if (expr.type === "variable") return "variable"
	return "variable"
}

function expressionVariable(expr: Expression | undefined) {
	if (!expr) return ""
	if (expr.type === "variable") return expr.name
	if (expr.type === "binary" && expr.left.type === "variable") return expr.left.name
	return ""
}

function expressionCompareValue(expr: Expression | undefined) {
	if (expr?.type === "binary" && expr.right.type === "literal") return String(expr.right.value ?? "")
	return ""
}

function expressionValidationMessage(expr: Expression | undefined): string | undefined {
	if (!expr) return "Expression is empty."
	if (expr.type === "variable") return validateVariableName(expr.name)
	if (expr.type === "binary") {
		return expressionValidationMessage(expr.left) || expressionValidationMessage(expr.right)
	}
	if (expr.type === "call" && expr.args.some((arg) => expressionValidationMessage(arg))) {
		return "One function argument is invalid."
	}
	return undefined
}

function validateVariableName(name: string) {
	const clean = String(name || "").trim()
	if (!clean) return "Variable name is required."
	if (clean.includes("(") || clean.includes(")")) return "Use the builder controls for function calls."
	if (!/^[a-zA-Z_$][\w$]*(\.[a-zA-Z_$][\w$]*|\[\d+\])*$/.test(clean)) {
		return "Use variable, nested.path, or items[0] format."
	}
	return undefined
}

function literalNumber(expr: Expression | undefined, fallback = 0) {
	return expr?.type === "literal" && Number.isFinite(Number(expr.value)) ? Number(expr.value) : fallback
}

function setControlExpressionMode(node: GraphNode, key: string, mode: string) {
	const next = getControlExpressionForMode(mode, expressionVariable((node as any)[key]), expressionCompareValue((node as any)[key]))
	;(node as any)[key] = next
	commitUndo()
}

function setControlExpressionVariable(node: GraphNode, key: string, variable: string) {
	const clean = variable.trim()
	const current = (node as any)[key] as Expression | undefined
	if (expressionMode(current) === "equals") {
		;(node as any)[key] = {
			type: "binary",
			op: "==",
			left: { type: "variable", name: clean },
			right: { type: "literal", value: expressionCompareValue(current) },
		}
	} else {
		;(node as any)[key] = clean ? { type: "variable", name: clean } : { type: "literal", value: true }
	}
	commitUndo()
}

function setControlExpressionCompareValue(node: GraphNode, key: string, value: string) {
	const variable = expressionVariable((node as any)[key]) || "value"
	;(node as any)[key] = {
		type: "binary",
		op: "==",
		left: { type: "variable", name: variable },
		right: { type: "literal", value },
	}
	commitUndo()
}

function setControlString(node: GraphNode, key: string, value: string) {
	;(node as any)[key] = value.trim() || key
	commitUndo()
}

function setControlNumber(node: GraphNode, key: string, value: number) {
	;(node as any)[key] = Number.isFinite(value) ? value : 1
	commitUndo()
}

function setControlLiteralNumber(node: GraphNode, key: string, value: number) {
	;(node as any)[key] = { type: "literal", value: Number.isFinite(value) ? value : 0 }
	commitUndo()
}

function getControlExpressionForMode(mode: string, variable: string, compareValue: string): Expression {
	if (mode === "false") return { type: "literal", value: false }
	if (mode === "variable") return { type: "variable", name: variable || "value" }
	if (mode === "equals") {
		return {
			type: "binary",
			op: "==",
			left: { type: "variable", name: variable || "value" },
			right: { type: "literal", value: compareValue },
		}
	}
	return { type: "literal", value: true }
}

function setSwitchCaseValue(node: Extract<GraphNode, { type: "switch" }>, index: number, value: string) {
	if (!node.cases[index]) return
	node.cases[index].value = value
	commitUndo()
}

function addSwitchCase(node: Extract<GraphNode, { type: "switch" }>) {
	node.cases.push({ value: `case${node.cases.length + 1}`, port: `case:${node.cases.length}` })
	commitUndo()
}

function deleteSwitchCase(node: Extract<GraphNode, { type: "switch" }>, index: number) {
	node.cases.splice(index, 1)
	commitUndo()
}

function addVariableNode(type: "string" | "number" | "boolean" | "color") {
	const canvasPoint = contextMenu.value.canvasPoint ?? { x: 100, y: 200 }
	const defaults: Record<string, string | number | boolean> = { string: "", number: 0, boolean: true, color: "#ffffff" }
	const vn: AutomationVariableNode = {
		id: nanoid(),
		name: "",
		type,
		value: defaults[type],
		x: canvasPoint.x,
		y: canvasPoint.y,
	}
	variableNodes.value.push(vn)
	closeContextMenu()
	commitUndo()
}

function deleteVariableNode(id: string) {
	const idx = variableNodes.value.findIndex((vn) => vn.id === id)
	if (idx >= 0) {
		variableNodes.value.splice(idx, 1)
		// Also remove any wires connected to this node
		dataWires.value = dataWires.value.filter((w) => w.fromNode !== id && w.toNode !== id)
		commitUndo()
	}
}

function updateVariableNodeValue(id: string, value: string | number | boolean) {
	const vn = variableNodes.value.find((v) => v.id === id)
	if (vn) {
		vn.value = value
		commitUndo()
	}
}

function updateVariableNodeName(id: string, name: string) {
	const vn = variableNodes.value.find((v) => v.id === id)
	if (vn) {
		vn.name = name
		commitUndo()
	}
}

const inlineEditNodeId = ref<string>()
const inlineEditInput = ref<HTMLInputElement>()

function startInlineEdit(nodeId: string) {
	inlineEditNodeId.value = nodeId
	nextTick(() => {
		const el = Array.isArray(inlineEditInput.value) ? inlineEditInput.value[0] : inlineEditInput.value
		el?.focus()
		el?.select()
	})
}

function commitInlineEdit(event: Event, node: NodeData) {
	const input = event.target as HTMLInputElement
	const vn = variableNodes.value.find((v) => v.id === node.id)
	if (vn) {
		// Parse the value based on type
		const raw = input.value
		if (vn.type === "number") {
			const num = Number(raw)
			if (!isNaN(num)) vn.value = num
		} else if (vn.type === "boolean") {
			vn.value = raw === "true" || raw === "1"
		} else {
			vn.value = raw
		}
		commitUndo()
	}
	inlineEditNodeId.value = undefined
}

function cancelInlineEdit() {
	inlineEditNodeId.value = undefined
}

function startResize(event: PointerEvent, node: NodeData) {
	event.preventDefault()
	const startX = event.clientX
	const startWidth = node.width ?? NODE_WIDTH
	const target = event.currentTarget as HTMLElement
	target.setPointerCapture(event.pointerId)

	// Compute dynamic min width: base 100 + longest port label (~7px per char)
	const allPorts = [...(node.inputPorts ?? []), ...(node.outputPorts ?? [])]
	const maxLabelLen = allPorts.reduce((max, p) => Math.max(max, p.label.length), 0)
	const minWidth = Math.max(120, 80 + maxLabelLen * 7)

	function onMove(me: PointerEvent) {
		const dx = (me.clientX - startX) / zoom.value
		const newWidth = Math.max(minWidth, Math.round(startWidth + dx))
		nodeSizes.value[node.id] = { width: newWidth }
	}
	function onUp() {
		target.removeEventListener("pointermove", onMove)
		target.removeEventListener("pointerup", onUp)
		commitUndo()
	}
	target.addEventListener("pointermove", onMove)
	target.addEventListener("pointerup", onUp)
}


onMounted(() => {
	window.addEventListener("keydown", handleKeydown)
	window.addEventListener("keyup", handleKeyup)
	window.addEventListener("click", handleWindowClick)
})
onUnmounted(() => {
	window.removeEventListener("keydown", handleKeydown)
	window.removeEventListener("keyup", handleKeyup)
	window.removeEventListener("click", handleWindowClick)
	pausePlayheadPreview()
})
</script>

<style scoped>
.node-automation {
	background: #151515;
	color: var(--text-color);
	display: flex;
	flex: 1;
	flex-direction: column;
	min-height: 0;
}

.node-automation__toolbar {
	align-items: center;
	background: #202020;
	border-bottom: 1px solid #343434;
	display: flex;
	gap: 1rem;
	justify-content: space-between;
	padding: 0.85rem 1rem;
}

.node-automation__toolbar h2,
.node-automation__details h3 {
	margin: 0;
}

.node-automation__eyebrow {
	color: #e9aaff;
	font-size: 0.72rem;
	font-weight: 700;
	letter-spacing: 0;
	margin: 0 0 0.2rem;
	text-transform: uppercase;
}

.node-automation__body {
	display: grid;
	flex: 1;
	grid-template-columns: minmax(0, 1fr) 320px;
	min-height: 0;
}

.node-automation__canvas {
	background-color: #202020;
	background-image: linear-gradient(#353535 1px, transparent 1px), linear-gradient(90deg, #353535 1px, transparent 1px);
	background-size: 42px 42px;
	border: 2px solid #8b35e6;
	margin: 0.75rem;
	overflow: auto;
	position: relative;
}

.node-automation__canvas.panning {
	cursor: grabbing;
}

.node-automation__canvas.space-held {
	cursor: grab;
}

.node-automation__canvas-controls {
	align-items: center;
	background: rgb(15 15 15 / 0.88);
	border: 1px solid #454545;
	border-radius: 6px;
	display: flex;
	gap: 0.35rem;
	left: 0.75rem;
	padding: 0.35rem;
	position: sticky;
	top: 0.75rem;
	width: max-content;
	z-index: 4;
}

.node-automation__canvas-controls button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 2rem;
	justify-content: center;
	width: 2rem;
}

.node-automation__canvas-controls button.active {
	background: #8b35e6;
	border-color: #e9aaff;
}

.node-automation__canvas-controls span {
	color: #e9e9e9;
	font-size: 0.8rem;
	min-width: 3rem;
	text-align: center;
}

.node-automation__canvas-controls .node-automation__control-divider {
	background: #454545;
	display: block;
	height: 1.35rem;
	min-width: 1px;
	width: 1px;
}

.node-automation__canvas-search {
	align-items: center;
	background: rgb(0 0 0 / 0.72);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 6px;
	display: flex;
	gap: 0.35rem;
	padding: 0.3rem 0.5rem;
	pointer-events: auto;
	position: absolute;
	right: 0.75rem;
	top: 3.5rem;
	z-index: 20;
}

.node-automation__canvas-search i {
	color: rgb(255 255 255 / 0.6);
	font-size: 1.1rem;
}

.node-automation__canvas-search input {
	background: transparent;
	border: none;
	color: #eee;
	font-size: 0.8rem;
	outline: none;
	width: 10rem;
}

.node-automation__canvas-search input::placeholder {
	color: rgb(255 255 255 / 0.35);
}

.node-automation__search-count {
	color: rgb(255 255 255 / 0.55);
	font-size: 0.75rem;
	min-width: 2.5rem;
	text-align: center;
	white-space: nowrap;
}

.node-automation__canvas-search button {
	align-items: center;
	background: transparent;
	border: none;
	border-radius: 3px;
	color: rgb(255 255 255 / 0.7);
	cursor: pointer;
	display: flex;
	font-size: 1rem;
	justify-content: center;
	padding: 0.15rem;
}

.node-automation__canvas-search button:hover {
	background: rgb(255 255 255 / 0.12);
}

.node-automation__subgraph-breadcrumb {
	align-items: center;
	background: rgb(15 15 15 / 0.9);
	border: 1px solid #7041a6;
	border-radius: 6px;
	color: #f2e8ff;
	display: flex;
	gap: 0.45rem;
	left: 0.75rem;
	padding: 0.35rem 0.55rem;
	position: sticky;
	top: 3.45rem;
	width: max-content;
	z-index: 4;
}

.node-automation__subgraph-breadcrumb button {
	align-items: center;
	background: #241333;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: #f2e8ff;
	cursor: pointer;
	display: flex;
	gap: 0.25rem;
	padding: 0.3rem 0.55rem;
}

.node-automation__subgraph-breadcrumb small {
	color: rgb(255 255 255 / 0.62);
}

.node-automation__wire-health {
	align-items: center;
	background: rgb(61 33 25 / 0.94);
	border: 1px solid rgb(239 154 154 / 0.5);
	border-radius: 6px;
	box-shadow: 0 12px 28px rgb(0 0 0 / 0.32);
	color: #fff4f4;
	display: grid;
	gap: 0.45rem;
	grid-template-columns: auto minmax(0, 1fr) auto auto;
	left: 0.75rem;
	max-width: min(42rem, calc(100% - 1.5rem));
	padding: 0.55rem 0.65rem;
	pointer-events: auto;
	position: sticky;
	top: 4.25rem;
	z-index: 22;
}

.node-automation__wire-health > i {
	color: #ef9a9a;
	font-size: 1.15rem;
}

.node-automation__wire-health div {
	display: grid;
	min-width: 0;
}

.node-automation__wire-health strong,
.node-automation__wire-health small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__wire-health small {
	color: #ffd6d6;
	font-size: 0.72rem;
}

.node-automation__wire-health button {
	background: rgb(255 255 255 / 0.1);
	border: 1px solid rgb(255 255 255 / 0.18);
	border-radius: 4px;
	color: #fff;
	cursor: pointer;
	font-size: 0.72rem;
	font-weight: 700;
	padding: 0.25rem 0.5rem;
}

.node-automation__wire-health button:hover {
	background: rgb(239 83 80 / 0.32);
	border-color: rgb(239 154 154 / 0.72);
}

.node-automation__node.search-dimmed {
	opacity: 0.3;
}

.node-automation__node.search-match {
	box-shadow: 0 0 0 2px #ffcc00;
}

.node-automation__minimap {
	background: rgb(0 0 0 / 0.5);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 4px;
	bottom: 0.75rem;
	cursor: crosshair;
	float: right;
	height: 120px;
	pointer-events: auto;
	position: sticky;
	width: 180px;
	z-index: 18;
}

.node-automation__minimap-node--trigger { fill: #4fc3f7; }
.node-automation__minimap-node--action { fill: #81c784; }
.node-automation__minimap-node--conversion { fill: #4dd0e1; }
.node-automation__minimap-node--queue { fill: #ffcf5a; }
.node-automation__minimap-node--stack { fill: #ba68c8; }
.node-automation__minimap-node--time { fill: #ffb74d; }
.node-automation__minimap-node--flow { fill: #4dd0e1; }
.node-automation__minimap-node--floating { fill: #a1887f; }

.node-automation__minimap-edge {
	stroke: rgb(255 255 255 / 0.25);
	stroke-width: 1.5;
}

.node-automation__minimap-data-wire {
	stroke-width: 1;
	opacity: 0.6;
}

.node-automation__minimap-viewport {
	fill: rgb(255 255 255 / 0.08);
	stroke: rgb(255 255 255 / 0.55);
	stroke-width: 2;
	vector-effect: non-scaling-stroke;
}

.node-automation__preview-status {
	align-items: center;
	background: rgb(0 0 0 / 0.28);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 4px;
	display: grid;
	gap: 0.15rem;
	grid-template-columns: 8rem minmax(6rem, 1fr) auto;
	min-width: 20rem;
	padding: 0.35rem 0.5rem;
}

.node-automation__preview-status strong,
.node-automation__preview-status small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__preview-status strong {
	font-size: 0.76rem;
}

.node-automation__preview-status small {
	color: #d6d6d6;
	font-size: 0.7rem;
	justify-self: end;
}

.node-automation__preview-meter {
	background: #101010;
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 999px;
	height: 0.42rem;
	overflow: hidden;
}

.node-automation__preview-meter span {
	background: linear-gradient(90deg, #e9aaff, #2ed47a);
	display: block;
	height: 100%;
	min-width: 0;
	transition: width 90ms linear;
}

.node-automation__surface {
	position: relative;
	transform-origin: 0 0;
}

.node-automation__edges {
	inset: 0;
	min-height: 100%;
	min-width: 100%;
	position: absolute;
	z-index: 1;
}

.node-automation__lane {
	background: rgb(255 255 255 / 0.035);
	border: 1px solid rgb(255 255 255 / 0.1);
	border-radius: 8px;
	position: absolute;
	z-index: 0;
}

.node-automation__rubber-band {
	background: rgb(139 53 230 / 0.12);
	border: 1.5px dashed #e9aaff;
	border-radius: 3px;
	pointer-events: none;
	position: absolute;
	z-index: 5;
}

.node-automation__ghost-node {
	align-items: center;
	background: rgb(139 53 230 / 0.18);
	border: 2px dashed #e9aaff;
	border-radius: 10px;
	color: #e9aaff;
	display: flex;
	font-size: 0.8rem;
	gap: 0.35rem;
	height: 74px;
	justify-content: center;
	opacity: 0.7;
	pointer-events: none;
	position: absolute;
	width: 220px;
	z-index: 4;
}

.node-automation__lane span {
	background: rgb(16 16 16 / 0.86);
	border: 1px solid rgb(255 255 255 / 0.12);
	border-radius: 999px;
	color: #e9e9e9;
	font-size: 0.72rem;
	font-weight: 700;
	left: 0.75rem;
	letter-spacing: 0;
	padding: 0.2rem 0.5rem;
	position: absolute;
	top: 0.45rem;
}

.node-automation__lane--main {
	border-color: rgb(233 170 255 / 0.3);
}

.node-automation__lane--floating {
	border-color: rgb(255 155 215 / 0.35);
}

.node-automation__lane--stack {
	border-color: rgb(255 223 107 / 0.35);
}

.node-automation__lane--time {
	border-color: rgb(104 211 145 / 0.35);
}

.node-automation__lane--flow {
	border-color: rgb(100 181 246 / 0.35);
}

.node-automation__edge {
	fill: none;
	stroke: #e9aaff;
	stroke-linecap: round;
	stroke-width: 2.5px;
}

.node-automation__edge--dragging {
	fill: none;
	stroke: #e9aaff;
	stroke-dasharray: 6 4;
	stroke-linecap: round;
	stroke-width: 2.5px;
	opacity: 0.7;
}

.node-automation__edge.active {
	stroke: #2ed47a;
	stroke-width: 4px;
}

.node-automation__edge.selected {
	stroke: #ffcc00;
	stroke-width: 3.5px;
}

.node-automation__edge-hit {
	fill: none;
	pointer-events: stroke;
	stroke: transparent;
	stroke-linecap: round;
	stroke-width: 22px;
}

.node-automation__edge-hit.active {
	stroke: rgb(46 212 122 / 0.15);
}

.node-automation__edge-label {
	pointer-events: none;
}

.node-automation__edge-label rect {
	fill: rgb(18 18 22 / 0.92);
	stroke: rgb(233 170 255 / 0.42);
	stroke-width: 1px;
}

.node-automation__edge-label text {
	fill: #f7e7ff;
	font-size: 0.72rem;
	font-weight: 700;
	letter-spacing: 0;
}

.node-automation__alignment-guide {
	pointer-events: none;
	stroke: #ff6b6b;
	stroke-dasharray: 4 3;
	stroke-width: 1px;
}

.node-automation__data-wire-hit {
	fill: none;
	pointer-events: stroke;
	stroke: transparent;
	stroke-linecap: round;
	stroke-width: 16px;
	cursor: pointer;
}

.node-automation__data-wire {
	fill: none;
	pointer-events: none;
	stroke-linecap: round;
	stroke-width: 2px;
}

.node-automation__data-wire.selected {
	stroke-width: 3.5px;
	filter: drop-shadow(0 0 4px currentColor);
}

.node-automation__data-wire.invalid {
	stroke-dasharray: 8 5;
	stroke-width: 3px;
	filter: drop-shadow(0 0 5px rgba(239, 83, 80, 0.6));
}

.node-automation__data-wire.removing {
	stroke: #ff4444;
	stroke-width: 3px;
	opacity: 0;
	transition: opacity 0.3s ease-out;
}

.node-automation__data-wire--dragging {
	stroke-dasharray: 6 4;
	opacity: 0.7;
	animation: wire-dash 0.4s linear infinite;
}

@keyframes wire-dash {
	to { stroke-dashoffset: -10; }
}

.node-automation__node {
	align-items: center;
	background: #181818;
	border: 2px solid #7d32d4;
	border-radius: 6px;
	box-shadow: 0 10px 24px rgb(0 0 0 / 0.28);
	color: white;
	cursor: grab;
	display: grid;
	gap: 0.45rem 0.65rem;
	grid-template-columns: 2rem minmax(0, 1fr) auto;
	grid-template-rows: auto;
	min-height: 74px;
	padding: 0.7rem;
	position: absolute;
	text-align: left;
	touch-action: none;
	z-index: 2;
}

.node-automation__handle {
	background: #111;
	border: 2px solid #e9aaff;
	border-radius: 999px;
	height: 0.85rem;
	position: absolute;
	top: 50%;
	transform: translateY(-50%);
	width: 0.85rem;
}

.node-automation__handle--in {
	left: -0.5rem;
}

.node-automation__handle--out {
	right: -0.5rem;
}

.node-automation__handle.connectable {
	cursor: crosshair;
	transition: background 0.15s, border-color 0.15s, transform 0.15s;
}

.node-automation__handle.connectable:hover {
	background: #e9aaff;
	border-color: #fff;
	transform: translateY(-50%) scale(1.3);
}

.node-automation__node.drop-target .node-automation__handle--out {
	background: #2ed47a;
	border-color: #d2ffe3;
}

.node-automation__node:active {
	cursor: grabbing;
}

.node-automation__node.selected {
	border-color: #ffdf6b;
	box-shadow: 0 0 0 3px rgb(255 223 107 / 0.2), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node:focus-visible {
	outline: 2px solid #80bdff;
	outline-offset: 2px;
}

.node-automation__node.preview-active {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.28), 0 0 30px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node.test-running {
	border-color: #4fc3f7;
	box-shadow: 0 0 0 3px rgb(79 195 247 / 0.3), 0 0 20px rgb(79 195 247 / 0.15);
	animation: pulse-border 0.8s ease-in-out infinite alternate;
}

.node-automation__node.test-success {
	border-color: #66bb6a;
	box-shadow: 0 0 0 2px rgb(102 187 106 / 0.25);
}

.node-automation__node.test-error {
	border-color: #ef5350;
	box-shadow: 0 0 0 2px rgb(239 83 80 / 0.3), 0 0 12px rgb(239 83 80 / 0.2);
}

.node-automation__node.missing {
	background: #2a1717;
	border-color: #ef5350;
	box-shadow: 0 0 0 2px rgb(239 83 80 / 0.16);
}

@keyframes pulse-border {
	from { opacity: 0.7; }
	to { opacity: 1; }
}

.node-automation__node.drop-target {
	border-color: #2ed47a;
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.22), 0 12px 28px rgb(0 0 0 / 0.35);
}

.node-automation__node--trigger {
	background: #40256c;
	border-color: #e9aaff;
}

.node-automation__node--action {
	background: #151515;
	border-color: #7d32d4;
}

.node-automation__node--conversion {
	background: color-mix(in srgb, #4dd0e1 10%, #151515);
	border-color: #4dd0e1;
}

.node-automation__node--queue {
	background: color-mix(in srgb, #ffcf5a 12%, #151515);
	border-color: #ffcf5a;
}

.node-automation__node--time {
	border-color: #68d391;
}

.node-automation__node--flow {
	border-color: #64b5f6;
}

.node-automation__node--if {
	border-color: #64b5f6;
}

.node-automation__node--switch {
	border-color: #7c4dff;
}

.node-automation__node--for,
.node-automation__node--forEach {
	border-color: #68d391;
}

.node-automation__node--while {
	border-color: #4db6ac;
}

.node-automation__node--break,
.node-automation__node--continue {
	border-color: #ef9a9a;
}

.node-automation__node--return {
	border-color: #ffab91;
}

.node-automation__node--floating {
	border-color: #ff9bd7;
}

.node-automation__node--variable {
	background: linear-gradient(135deg, rgb(38 50 56 / 0.96), rgb(20 28 31 / 0.96));
	border-color: #90a4ae;
	border-radius: 6px;
	border-style: dashed;
	box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.06), 0 8px 20px rgb(0 0 0 / 0.3);
	min-width: 150px;
	padding-left: 0.85rem;
	padding-right: 0.85rem;
}

.node-automation__node--variable::before {
	background: currentColor;
	border-radius: 999px;
	content: "";
	height: calc(100% - 1.2rem);
	left: 0.45rem;
	opacity: 0.28;
	position: absolute;
	top: 0.6rem;
	width: 0.22rem;
}

.node-automation__node--variable .node-automation__node-icon {
	background: rgb(255 255 255 / 0.16);
	border-radius: 999px;
}

.node-automation__node--variable .node-automation__node-badge {
	background: rgb(144 164 174 / 0.25);
	border: 1px solid rgb(144 164 174 / 0.45);
	color: #d9edf4;
}

.node-automation__node--trigger .node-automation__node-badge {
	background: #ffdf6b;
}

.node-automation__node.missing .node-automation__node-badge {
	background: #ef5350;
	color: #fff;
}

.node-automation__node-icon {
	align-items: center;
	background: rgb(255 255 255 / 0.12);
	border-radius: 4px;
	display: flex;
	font-size: 1.25rem;
	height: 2rem;
	justify-content: center;
}

.node-automation__node-text {
	display: grid;
	min-width: 0;
}

.node-automation__node-text strong,
.node-automation__node-text small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-text small {
	color: #d6d6d6;
	font-size: 0.78rem;
}

.node-automation__inline-edit input {
	background: rgba(0, 0, 0, 0.5);
	border: 1px solid #8b35e6;
	border-radius: 3px;
	color: #fff;
	font-size: 0.78rem;
	outline: none;
	padding: 0 0.2rem;
	width: 100%;
}

.node-automation__node-badge {
	background: #e9aaff;
	border-radius: 4px;
	color: #1b0f21;
	font-size: 0.7rem;
	font-weight: 700;
	padding: 0.2rem 0.35rem;
}

.node-automation__node-run {
	align-items: center;
	background: #4caf50;
	border-radius: 50%;
	color: #fff;
	cursor: pointer;
	display: flex;
	font-size: 0.7rem;
	height: 20px;
	justify-content: center;
	width: 20px;
}
.node-automation__node-run:hover {
	background: #66bb6a;
}

.node-automation__test-badge {
	border-radius: 50%;
	font-size: 0.65rem;
	font-weight: 700;
	height: 18px;
	line-height: 18px;
	text-align: center;
	width: 18px;
}

.node-automation__test-badge--ok {
	background: #66bb6a;
	color: #fff;
}

.node-automation__test-badge--error {
	background: #ef5350;
	color: #fff;
}

.node-automation__test-duration {
	background: rgba(79, 195, 247, 0.16);
	border: 1px solid rgba(79, 195, 247, 0.4);
	border-radius: 4px;
	color: #b8eaff;
	font-size: 0.68rem;
	font-weight: 700;
	padding: 0.12rem 0.28rem;
}

.node-automation__node-config {
	border-top: 1px solid rgb(255 255 255 / 0.1);
	display: grid;
	gap: 0;
	grid-column: 1 / -1;
	margin: 0;
	padding-top: 0.3rem;
}

.node-automation__node-config-line {
	display: flex;
	gap: 0.35rem;
	line-height: 1.25;
}

.node-automation__node-config-line dt {
	color: #b0b0b0;
	flex-shrink: 0;
	font-size: 0.68rem;
	font-weight: 600;
	max-width: 5.5rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-config-line dd {
	color: #e9e9e9;
	flex: 1;
	font-size: 0.68rem;
	margin: 0;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__node-ports {
	border-top: 1px solid rgb(255 255 255 / 0.1);
	grid-column: 1 / -1;
	padding-top: 0.25rem;
}

.node-automation__port-columns {
	display: flex;
	gap: 0.5rem;
	justify-content: space-between;
}

.node-automation__port-list {
	display: grid;
	gap: 0;
	list-style: none;
	margin: 0;
	padding: 0;
}

.node-automation__port-list--in {
	align-items: flex-start;
}

.node-automation__port-list--out {
	align-items: flex-end;
	margin-left: auto;
}

.node-automation__port {
	align-items: center;
	display: flex;
	gap: 0.25rem;
	line-height: 1.15;
}

.node-automation__port--out {
	justify-content: flex-end;
}

.node-automation__port-dot {
	border: 2px solid #7d32d4;
	border-radius: 50%;
	cursor: crosshair;
	flex-shrink: 0;
	height: 10px;
	position: relative;
	transition: transform 0.12s, box-shadow 0.12s;
	width: 10px;
}

/* Expanded invisible hit area so ports are easier to click at any zoom */
.node-automation__port-dot::before {
	content: "";
	inset: -6px;
	position: absolute;
}

.node-automation__port-dot:hover {
	box-shadow: 0 0 6px 2px currentColor;
	transform: scale(1.4);
}

.node-automation__port-dot.drag-valid {
	box-shadow: 0 0 0 4px rgb(46 212 122 / 0.3), 0 0 10px rgb(46 212 122 / 0.55);
	transform: scale(1.5);
}

.node-automation__port-dot.drag-invalid {
	background: #ef5350 !important;
	border-color: #ffb3b3 !important;
	box-shadow: 0 0 0 4px rgb(239 83 80 / 0.28), 0 0 12px rgb(239 83 80 / 0.65);
	transform: scale(1.55);
}

.node-automation__port-dot--in {
	border-color: #4a8a4d;
}

.node-automation__port-dot--out {
	border-color: #2980b9;
}

.node-automation__port-dot--exec {
	border-color: #e9aaff;
	background: #e9aaff44;
}

.node-automation__port-dot--exec.connected {
	background: #e9aaff;
}

.node-automation__port-dot--exec:hover {
	box-shadow: 0 0 6px 2px #e9aaff;
}

.node-automation__port-label {
	color: #d6d6d6;
	font-size: 0.65rem;
	max-width: 5rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__port-type {
	color: rgb(255 255 255 / 0.35);
	font-family: monospace;
	font-size: 0.58rem;
}

.node-automation__context-menu {
	background: var(--surface-b);
	border: 1px solid var(--surface-d);
	border-radius: 3px;
	box-shadow: 0 18px 45px rgb(0 0 0 / 0.42);
	color: var(--text-color);
	display: grid;
	gap: 0.35rem;
	max-height: min(32rem, calc(100vh - 1rem));
	overflow: auto;
	padding: 0.35rem;
	position: fixed;
	width: 340px;
	z-index: 20;
}

.node-automation__context-menu-header {
	align-items: center;
	background: var(--surface-c);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: flex;
	justify-content: space-between;
	padding: 0.5rem 0.55rem;
}

.node-automation__context-menu-header div {
	display: grid;
	gap: 0.1rem;
	min-width: 0;
}

.node-automation__context-menu-header span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__context-menu-header button {
	align-items: center;
	background: var(--surface-700);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 1.65rem;
	justify-content: center;
	width: 1.65rem;
}

.node-automation__context-menu-search {
	align-items: center;
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1rem 1fr;
	padding: 0.35rem 0.45rem;
}

.node-automation__context-menu-search input {
	background: transparent;
	border: 0;
	color: var(--text-color);
	min-width: 0;
	outline: 0;
}

.node-automation__menu-section {
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	overflow: hidden;
}

.node-automation__menu-hint {
	align-items: center;
	color: var(--text-color-secondary);
	display: flex;
	gap: 0.5rem;
	padding: 0.7rem;
}

.node-automation__menu-section-header,
.node-automation__menu-group-header {
	align-items: center;
	background: var(--surface-c);
	border: 0;
	border-bottom: 1px solid var(--surface-d);
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.45rem 0.55rem;
	width: 100%;
}

.node-automation__menu-utility-btn {
	align-items: center;
	background: var(--surface-c);
	border: 0;
	border-bottom: 1px solid var(--surface-d);
	color: var(--text-color-secondary);
	cursor: pointer;
	display: flex;
	gap: 0.4rem;
	padding: 0.5rem 0.55rem;
	width: 100%;
}

.node-automation__menu-utility-btn:hover {
	background: var(--surface-d);
	color: var(--text-color);
}

.node-automation__menu-section-header span,
.node-automation__menu-group-header span {
	align-items: center;
	display: flex;
	gap: 0.4rem;
	min-width: 0;
}

.node-automation__menu-groups {
	background: var(--surface-b);
	display: grid;
}

.node-automation__menu-subtitle {
	align-items: center;
	color: var(--text-color-secondary);
	display: flex;
	font-size: 0.72rem;
	font-weight: 700;
	gap: 0.35rem;
	letter-spacing: 0;
	padding: 0.45rem 0.5rem 0.1rem;
	text-transform: uppercase;
}

.node-automation__menu-group + .node-automation__menu-group {
	border-top: 1px solid var(--surface-d);
}

.node-automation__menu-group-header {
	background: var(--surface-a);
	font-size: 0.86rem;
	font-weight: 600;
	padding-left: 0.75rem;
}

.node-automation__menu-items {
	display: grid;
	padding: 0.2rem;
}

.node-automation__menu-items button {
	align-items: center;
	background: transparent;
	border: 1px solid transparent;
	border-radius: 2px;
	color: var(--text-color);
	cursor: pointer;
	display: grid;
	gap: 0.45rem;
	grid-template-columns: 1.35rem minmax(0, 1fr) auto;
	padding: 0.42rem 0.45rem;
	text-align: left;
}

.node-automation__menu-items button:hover {
	background: color-mix(in srgb, #8b35e6 24%, var(--surface-a));
	border-color: #8b35e6;
}

.node-automation__menu-items button:focus-visible {
	background: color-mix(in srgb, #8b35e6 28%, var(--surface-a));
	border-color: rgb(233 170 255 / 0.7);
	outline: 2px solid rgb(233 170 255 / 0.45);
	outline-offset: 1px;
}

.node-automation__menu-items span {
	display: grid;
	min-width: 0;
}

.node-automation__menu-items strong,
.node-automation__menu-items small {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__menu-items small {
	color: var(--text-color-secondary);
	font-size: 0.72rem;
}

.node-automation__menu-items em {
	background: #7d32d4;
	border-radius: 3px;
	color: white;
	font-size: 0.66rem;
	font-style: normal;
	font-weight: 700;
	padding: 0.12rem 0.28rem;
}

.node-automation__menu-items em.trigger {
	background: #c24cff;
	color: #19001f;
}

.node-automation__details {
	background: #111;
	border-left: 1px solid #343434;
	display: flex;
	flex-direction: column;
	gap: 0.85rem;
	padding: 1rem;
}

.node-automation__details.empty {
	justify-content: flex-start;
}

.node-automation__details-header {
	align-items: flex-start;
	display: flex;
	gap: 0.75rem;
	justify-content: space-between;
}

.node-automation__icon-button {
	align-items: center;
	background: #2c2c2c;
	border: 1px solid #454545;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	height: 2rem;
	justify-content: center;
	width: 2rem;
}

.node-automation__context-section {
	background: #181818;
	border: 1px solid #303030;
	border-radius: 6px;
	overflow: hidden;
}

.node-automation__context-header {
	align-items: center;
	background: #222;
	border: 0;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.7rem 0.8rem;
	width: 100%;
}

.node-automation__context-header span {
	align-items: center;
	display: flex;
	gap: 0.45rem;
}

.node-automation__config {
	max-height: 52vh;
	overflow: auto;
	padding: 0.55rem;
}

.node-automation__missing-schema {
	align-items: start;
	background: rgba(239, 83, 80, 0.1);
	border: 1px solid rgba(239, 83, 80, 0.35);
	border-radius: 5px;
	color: #ffd8d8;
	display: grid;
	gap: 0.35rem;
	padding: 0.75rem;
}

.node-automation__missing-schema i {
	color: #ff7777;
	font-size: 1.4rem;
}

.node-automation__missing-schema span,
.node-automation__missing-schema small {
	color: #ffbcbc;
}

.node-automation__quick-actions {
	display: grid;
	gap: 0.5rem;
	padding: 0.65rem;
}

.node-automation__action-picker {
	display: grid;
	gap: 0.5rem;
}

.node-automation__action-picker label {
	display: grid;
	gap: 0.3rem;
}

.node-automation__action-picker span {
	color: #d9d9d9;
	font-size: 0.78rem;
}

.node-automation__action-picker input,
.node-automation__action-picker select {
	background: #0e0e0e;
	border: 1px solid #4d4d4d;
	border-radius: 4px;
	color: var(--text-color);
	min-width: 0;
	padding: 0.55rem;
}

.node-automation__action-grid {
	display: grid;
	gap: 0.5rem;
	grid-template-columns: 1fr 1fr;
}

.node-automation__palette-list {
	display: grid;
	gap: 0.35rem;
	max-height: 13rem;
	overflow: auto;
	padding-right: 0.15rem;
}

.node-automation__palette-list button {
	align-items: center;
	background: #151515;
	border: 1px solid #3d3d3d;
	border-radius: 4px;
	color: var(--text-color);
	cursor: grab;
	display: grid;
	gap: 0.4rem;
	grid-template-columns: 1.25rem minmax(4rem, 0.7fr) minmax(0, 1fr);
	padding: 0.45rem 0.5rem;
	text-align: left;
}

.node-automation__palette-list button:active {
	cursor: grabbing;
}

.node-automation__palette-list span,
.node-automation__palette-list strong {
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__palette-list span {
	color: #bbb;
}

.node-automation__quick-actions button {
	align-items: center;
	background: #2b173d;
	border: 1px solid #7041a6;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: flex;
	gap: 0.45rem;
	padding: 0.65rem 0.75rem;
	text-align: left;
}

.node-automation__quick-actions button.danger {
	background: #3a171b;
	border-color: #8f3744;
}

.node-automation__quick-actions button:disabled {
	cursor: not-allowed;
	opacity: 0.45;
}

.node-automation__details dl {
	display: grid;
	gap: 0.75rem;
	margin: 0;
	padding: 0.75rem;
}

.node-automation__subgraphs {
	padding: 0.65rem;
}

.node-automation__subgraph-list {
	display: grid;
	gap: 0.4rem;
	list-style: none;
	margin: 0 0 0.5rem;
	padding: 0;
}

.node-automation__subgraph-item {
	align-items: center;
	background: #101010;
	border: 1px solid #303030;
	border-radius: 4px;
	display: grid;
	gap: 0.2rem;
	grid-template-columns: 1fr auto;
	padding: 0.5rem 0.6rem;
}

.node-automation__subgraph-item.focused {
	border-color: #e9aaff;
	box-shadow: 0 0 0 1px rgba(233, 170, 255, 0.25);
}

.node-automation__subgraph-name {
	align-items: center;
	display: flex;
	gap: 0.45rem;
	font-weight: 500;
}

.node-automation__subgraph-name input,
.node-automation__subgraph-params input,
.node-automation__subgraph-params select {
	background: #070707;
	border: 1px solid #333;
	border-radius: 4px;
	color: #eee;
	min-width: 0;
	padding: 0.35rem 0.45rem;
}

.node-automation__subgraph-name input {
	width: 100%;
}

.node-automation__subgraph-meta {
	color: #999;
	font-size: 0.75rem;
	grid-column: 1;
}

.node-automation__subgraph-tools {
	display: flex;
	flex-wrap: wrap;
	gap: 0.35rem;
	grid-column: 1 / -1;
}

.node-automation__subgraph-tools button,
.node-automation__subgraph-params button {
	background: #1e1e1e;
	border: 1px solid #3b3b3b;
	border-radius: 4px;
	color: #ddd;
	cursor: pointer;
	padding: 0.35rem 0.5rem;
}

.node-automation__subgraph-params {
	display: grid;
	gap: 0.35rem;
	grid-column: 1 / -1;
	margin-top: 0.35rem;
}

.node-automation__subgraph-params > div {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: minmax(0, 1fr) 6.5rem minmax(0, 1fr) auto;
}

.node-automation__subgraph-params strong {
	color: #ddd;
	font-size: 0.75rem;
	margin-top: 0.25rem;
	text-transform: uppercase;
}

.node-automation__subgraph-item > .danger {
	background: transparent;
	border: none;
	color: #ef5350;
	cursor: pointer;
	grid-row: 1 / 3;
	grid-column: 2;
	padding: 0.3rem;
}

.node-automation__add-subgraph {
	background: #1e1e1e;
	border: 1px dashed #555;
	border-radius: 4px;
	color: #ccc;
	cursor: pointer;
	padding: 0.5rem;
	width: 100%;
}

.node-automation__add-subgraph:hover {
	background: #2a2a2a;
	border-color: #e9aaff;
	color: #fff;
}

.node-automation__execution-header {
	align-items: center;
	background: #222;
	color: var(--text-color);
	display: flex;
	font-weight: 700;
	justify-content: space-between;
	padding: 0.7rem 0.8rem;
}

.node-automation__execution-header span {
	align-items: center;
	display: flex;
	gap: 0.45rem;
}

.node-automation__execution-header small {
	color: #b8eaff;
	font-size: 0.72rem;
	text-transform: uppercase;
}

.node-automation__execution-path {
	counter-reset: execution-step;
	display: grid;
	gap: 0.4rem;
	list-style: none;
	margin: 0;
	max-height: 13rem;
	overflow: auto;
	padding: 0.65rem;
}

.node-automation__execution-path li {
	align-items: center;
	background: #101010;
	border: 1px solid #303030;
	border-radius: 4px;
	counter-increment: execution-step;
	display: grid;
	gap: 0.15rem;
	grid-template-columns: 1fr auto;
	padding: 0.5rem 0.6rem;
}

.node-automation__execution-path li::before {
	color: #e9aaff;
	content: counter(execution-step, decimal-leading-zero);
	font-size: 0.68rem;
	font-weight: 800;
	grid-column: 1 / -1;
	letter-spacing: 0.04em;
}

.node-automation__execution-path span {
	font-weight: 700;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__execution-path small {
	color: #b8eaff;
	font-size: 0.72rem;
}

.node-automation__execution-path small.error {
	color: #ffb4b4;
	max-width: 12rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.node-automation__details dl div {
	display: grid;
	gap: 0.2rem;
}

.node-automation__details dt {
	color: #aaa;
	font-size: 0.78rem;
}

.node-automation__details dd {
	margin: 0;
	overflow-wrap: anywhere;
}

.node-automation__hint {
	color: #cfcfcf;
	line-height: 1.45;
	margin: 0;
}

.node-automation__variable-edit,
.node-automation__control-edit {
	display: grid;
	gap: 0.55rem;
}

.node-automation__variable-edit label,
.node-automation__control-edit label {
	display: flex;
	flex-direction: column;
	gap: 0.3rem;
}

.node-automation__variable-edit label span,
.node-automation__control-edit label span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	font-weight: 600;
	text-transform: uppercase;
}

.node-automation__variable-edit input,
.node-automation__variable-edit select,
.node-automation__control-edit input,
.node-automation__control-edit select {
	background: var(--surface-a);
	border: 1px solid var(--surface-d);
	border-radius: 4px;
	color: var(--text-color);
	font-size: 0.85rem;
	padding: 0.35rem 0.5rem;
}

.node-automation__case-list {
	display: grid;
	gap: 0.4rem;
}

.node-automation__case-list > div {
	display: grid;
	gap: 0.35rem;
	grid-template-columns: 1fr auto;
}

.node-automation__case-list button {
	align-items: center;
	background: #262626;
	border: 1px solid #3a3a3a;
	border-radius: 4px;
	color: var(--text-color);
	cursor: pointer;
	display: inline-flex;
	gap: 0.25rem;
	justify-content: center;
	padding: 0.35rem 0.55rem;
}

.node-automation__case-list button.danger {
	color: #ffb4b4;
}

.node-automation__expression-summary {
	background: #101010;
	border: 1px solid #303030;
	border-radius: 5px;
	display: grid;
	gap: 0.25rem;
	padding: 0.5rem;
}

.node-automation__expression-summary code {
	color: #b8eaff;
	font-family: "Cascadia Code", "Consolas", monospace;
	font-size: 0.78rem;
	overflow-wrap: anywhere;
}

.node-automation__expression-summary small {
	color: #9fd0a7;
	font-size: 0.72rem;
}

.node-automation__expression-summary.invalid {
	border-color: rgba(239, 83, 80, 0.55);
}

.node-automation__expression-summary.invalid small {
	color: #ffb4b4;
}

.node-automation__resize-handle {
	bottom: 0;
	cursor: ew-resize;
	position: absolute;
	right: -4px;
	top: 0;
	width: 8px;
	z-index: 10;
}

.node-automation__resize-handle:hover,
.node-automation__resize-handle:active {
	background: rgba(139, 53, 230, 0.4);
	border-radius: 0 4px 4px 0;
}

.sr-only {
	border: 0;
	clip: rect(0, 0, 0, 0);
	height: 1px;
	margin: -1px;
	overflow: hidden;
	padding: 0;
	position: absolute;
	white-space: nowrap;
	width: 1px;
}
</style>
