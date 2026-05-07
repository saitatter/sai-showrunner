<template>
	<div class="missing-schema-notice">
		<i class="mdi mdi-alert-circle-outline" />
		<strong>{{ title }}</strong>
		<span>{{ source }}</span>
		<small>{{ message }}</small>
	</div>
</template>

<script setup lang="ts">
defineProps<{
	title: string
	source: string
	message: string
}>()
</script>

<style scoped>
.missing-schema-notice {
	align-items: start;
	background: rgba(239, 83, 80, 0.1);
	border: 1px solid rgba(239, 83, 80, 0.35);
	border-radius: 5px;
	color: #ffd8d8;
	display: grid;
	gap: 0.35rem;
	padding: 0.75rem;
}

.missing-schema-notice i {
	color: #ff7777;
	font-size: 1.4rem;
}

.missing-schema-notice span,
.missing-schema-notice small {
	color: #ffbcbc;
}
</style>
