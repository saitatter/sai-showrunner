<template>
	<div
		class="showrunner-context-menu"
		:style="{ left: `${x}px`, top: `${y}px`, width }"
		@click.stop
		@pointerdown.stop
		@mousedown.stop
		@contextmenu.prevent.stop
	>
		<header class="showrunner-context-menu__header">
			<div>
				<strong>{{ title }}</strong>
				<span v-if="subtitle">{{ subtitle }}</span>
			</div>
			<button type="button" aria-label="Close menu" @click="$emit('close')">
				<i class="mdi mdi-close" />
			</button>
		</header>
		<slot name="search" />
		<slot />
	</div>
</template>

<script setup lang="ts">
withDefaults(
	defineProps<{
		x: number
		y: number
		title: string
		subtitle?: string
		width?: string
	}>(),
	{
		width: "340px",
	}
)

defineEmits<{
	close: []
}>()
</script>

<style scoped>
.showrunner-context-menu {
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
	z-index: 20;
}

.showrunner-context-menu__header {
	align-items: center;
	background: var(--surface-c);
	border: 1px solid var(--surface-d);
	border-radius: 2px;
	display: flex;
	justify-content: space-between;
	padding: 0.5rem 0.55rem;
}

.showrunner-context-menu__header div {
	display: grid;
	gap: 0.1rem;
	min-width: 0;
}

.showrunner-context-menu__header span {
	color: var(--text-color-secondary);
	font-size: 0.75rem;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.showrunner-context-menu__header button {
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
</style>
