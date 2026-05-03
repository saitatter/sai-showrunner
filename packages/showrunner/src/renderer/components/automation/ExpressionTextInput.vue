<template>
	<div class="expression-input" :class="{ invalid }">
		<pre class="expression-input__highlight" aria-hidden="true"><span
			v-for="(token, index) in tokens"
			:key="`${index}:${token.text}`"
			:class="`expression-input__token expression-input__token--${token.kind}`"
		>{{ token.text }}</span><span v-if="!localValue" class="expression-input__placeholder">{{ placeholder }}</span></pre>
		<input
			:value="localValue"
			:list="list"
			:placeholder="placeholder"
			spellcheck="false"
			@input="onInput"
			@change="$emit('change', localValue)"
		/>
	</div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from "vue"

const props = defineProps<{
	modelValue: string
	list?: string
	placeholder?: string
	invalid?: boolean
}>()

const emit = defineEmits<{
	"update:modelValue": [value: string]
	change: [value: string]
}>()

const localValue = ref(props.modelValue ?? "")

watch(
	() => props.modelValue,
	(value) => {
		if (value !== localValue.value) localValue.value = value ?? ""
	}
)

const tokens = computed(() => tokenizeExpression(localValue.value))

function onInput(event: Event) {
	localValue.value = (event.target as HTMLInputElement).value
	emit("update:modelValue", localValue.value)
}

function tokenizeExpression(source: string) {
	const result: Array<{ text: string; kind: string }> = []
	const pattern =
		/(\{\{|\}\}|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\b(?:true|false|null|undefined)\b|\b(?:len|includes|toString|toNumber|toBoolean|min|max|keys|values|sum|avg|round|floor|ceil|abs|clamp)\b(?=\s*\()|\d+(?:\.\d+)?|[=!<>]=?|&&|\|\||[()+\-*/%.,[\]]|[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*|\[\d+\])*)/g
	let cursor = 0
	for (const match of source.matchAll(pattern)) {
		const index = match.index ?? 0
		if (index > cursor) result.push({ text: source.slice(cursor, index), kind: "plain" })
		result.push({ text: match[0], kind: classifyToken(match[0]) })
		cursor = index + match[0].length
	}
	if (cursor < source.length) result.push({ text: source.slice(cursor), kind: "plain" })
	return result.length ? result : [{ text: "", kind: "plain" }]
}

function classifyToken(token: string) {
	if (/^["']/.test(token)) return "string"
	if (/^\d/.test(token)) return "number"
	if (/^(true|false|null|undefined)$/.test(token)) return "literal"
	if (/^(len|includes|toString|toNumber|toBoolean|min|max|keys|values|sum|avg|round|floor|ceil|abs|clamp)$/.test(token)) {
		return "builtin"
	}
	if (/^(\{\{|\}\}|[=!<>]=?|&&|\|\||[()+\-*/%.,[\]])$/.test(token)) return "operator"
	if (token.includes(".") || token.includes("[")) return "path"
	return "identifier"
}
</script>

<style scoped>
.expression-input {
	display: grid;
	position: relative;
}

.expression-input input,
.expression-input__highlight {
	background: #080808;
	border: 1px solid #333;
	border-radius: 4px;
	color: transparent;
	font-family: "JetBrains Mono", "Cascadia Code", Consolas, monospace;
	font-size: 0.82rem;
	line-height: 1.35;
	margin: 0;
	min-height: 2rem;
	overflow: hidden;
	padding: 0.45rem 0.55rem;
	white-space: pre;
}

.expression-input input {
	caret-color: #fff;
	position: relative;
	width: 100%;
	z-index: 2;
}

.expression-input input::placeholder {
	color: transparent;
}

.expression-input__highlight {
	inset: 0;
	pointer-events: none;
	position: absolute;
	z-index: 1;
}

.expression-input.invalid input,
.expression-input.invalid .expression-input__highlight {
	border-color: #ef5350;
}

.expression-input__placeholder {
	color: #666;
}

.expression-input__token--plain,
.expression-input__token--identifier {
	color: #d9d9d9;
}

.expression-input__token--path {
	color: #81c784;
}

.expression-input__token--builtin {
	color: #ce93d8;
}

.expression-input__token--number {
	color: #4fc3f7;
}

.expression-input__token--string {
	color: #ffcc80;
}

.expression-input__token--literal {
	color: #ffb74d;
}

.expression-input__token--operator {
	color: #90caf9;
}
</style>
