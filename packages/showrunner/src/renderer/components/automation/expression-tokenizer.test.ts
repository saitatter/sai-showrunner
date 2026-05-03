import { describe, expect, it } from "vitest"
import { EXPRESSION_BUILTINS, classifyExpressionToken, tokenizeExpression } from "./expression-tokenizer"

describe("expression tokenizer", () => {
	it("matches the graph expression builtin list", () => {
		expect(EXPRESSION_BUILTINS).toEqual([
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
		])
	})

	it("highlights supported builtins and leaves unsupported names as identifiers", () => {
		expect(classifyExpressionToken("startsWith")).toBe("builtin")
		expect(classifyExpressionToken("slice")).toBe("builtin")
		expect(classifyExpressionToken("sum")).toBe("identifier")
		expect(classifyExpressionToken("clamp")).toBe("identifier")
	})

	it("tokenizes paths, literals, operators, and strings without dropping spacing", () => {
		const tokens = tokenizeExpression(`payload.name == "Sai" && len(items) > 0`)
		expect(tokens.map((token) => token.text).join("")).toBe(`payload.name == "Sai" && len(items) > 0`)
		expect(tokens).toContainEqual({ text: "payload.name", kind: "path" })
		expect(tokens).toContainEqual({ text: "len", kind: "builtin" })
		expect(tokens).toContainEqual({ text: `"Sai"`, kind: "string" })
		expect(tokens).toContainEqual({ text: "&&", kind: "operator" })
	})
})
