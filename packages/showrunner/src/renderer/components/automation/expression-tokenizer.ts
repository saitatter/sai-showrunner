import type { BuiltinFn } from "ShowRunner-schema"

export type ExpressionTokenKind =
	| "plain"
	| "identifier"
	| "path"
	| "builtin"
	| "number"
	| "string"
	| "literal"
	| "operator"

export interface ExpressionToken {
	text: string
	kind: ExpressionTokenKind
}

export const EXPRESSION_BUILTINS = [
	"len",
	"includes",
	"startsWith",
	"endsWith",
	"toString",
	"toNumber",
	"toBoolean",
	"floor",
	"ceil",
	"round",
	"abs",
	"min",
	"max",
	"keys",
	"values",
	"slice",
	"concat",
] as const satisfies readonly BuiltinFn[]

const BUILTIN_SET = new Set<string>(EXPRESSION_BUILTINS)
const BUILTIN_PATTERN = EXPRESSION_BUILTINS.join("|")
const TOKEN_PATTERN = new RegExp(
	`(\\{\\{|\\}\\}|"(?:[^"\\\\]|\\\\.)*"|'(?:[^'\\\\]|\\\\.)*'|\\b(?:true|false|null|undefined)\\b|\\b(?:${BUILTIN_PATTERN})\\b(?=\\s*\\()|\\d+(?:\\.\\d+)?|[=!<>]=?|&&|\\|\\||[()+\\-*/%.,[\\]]|[A-Za-z_$][\\w$]*(?:\\.[A-Za-z_$][\\w$]*|\\[\\d+\\])*)`,
	"g"
)

export function tokenizeExpression(source: string): ExpressionToken[] {
	const result: ExpressionToken[] = []
	let cursor = 0
	for (const match of source.matchAll(TOKEN_PATTERN)) {
		const index = match.index ?? 0
		if (index > cursor) result.push({ text: source.slice(cursor, index), kind: "plain" })
		result.push({ text: match[0], kind: classifyExpressionToken(match[0]) })
		cursor = index + match[0].length
	}
	if (cursor < source.length) result.push({ text: source.slice(cursor), kind: "plain" })
	return result.length ? result : [{ text: "", kind: "plain" }]
}

export function classifyExpressionToken(token: string): ExpressionTokenKind {
	if (/^["']/.test(token)) return "string"
	if (/^\d/.test(token)) return "number"
	if (/^(true|false|null|undefined)$/.test(token)) return "literal"
	if (BUILTIN_SET.has(token)) return "builtin"
	if (/^(\{\{|\}\}|[=!<>]=?|&&|\|\||[()+\-*/%.,[\]])$/.test(token)) return "operator"
	if (token.includes(".") || token.includes("[")) return "path"
	return "identifier"
}
