# Graph Execution Engine — Turing Complete

Replaces the current linear `SequenceRunner` (which iterates `sequence.actions[]`) with a compiled graph VM that supports branching, loops, subgraphs, and typed data flow.

## Architecture

```
AutomationData (graph model)
    ↓
GraphCompiler.compile()
    ↓
Program { instructions[], entryPoints, subgraphTable }
    ↓
GraphVM.execute(program, context, debugger?)
    ↓
real-time IPC events for UI (same hooks as before)
```

The graph is compiled once when the automation is saved/loaded. The VM executes the flat instruction array with a program counter — no recursive graph traversal at runtime.

## Data Model Changes

### New node types (added to `SequenceActions`)

```typescript
// libs/showrunner-schema/src/types/sequence.ts

interface IfNode {
  id: string
  type: "if"
  condition: Expression       // compiled expression (see below)
  thenBranch: string         // node id for true path
  elseBranch?: string        // node id for false path (falls through if absent)
}

interface SwitchNode {
  id: string
  type: "switch"
  expression: Expression
  cases: { value: any; target: string }[]
  defaultTarget?: string
}

interface ForLoopNode {
  id: string
  type: "for"
  variable: string           // loop counter variable name
  start: Expression
  end: Expression
  step: Expression
  body: string               // entry node id of loop body
  next: string               // node id after loop completes
}

interface ForEachNode {
  id: string
  type: "forEach"
  variable: string           // current item variable name
  indexVariable?: string     // optional index variable
  collection: Expression     // expression resolving to array
  body: string
  next: string
}

interface WhileNode {
  id: string
  type: "while"
  condition: Expression
  body: string
  next: string
  maxIterations?: number     // safety cap (default 10000)
}

interface BreakNode {
  id: string
  type: "break"
}

interface ContinueNode {
  id: string
  type: "continue"
}

interface ReturnNode {
  id: string
  type: "return"
  outputs?: Record<string, Expression>
}

interface SubgraphCallNode {
  id: string
  type: "subgraphCall"
  subgraphId: string
  inputs: Record<string, Expression>  // maps subgraph param names to expressions
}
```

### Subgraph definition

```typescript
// libs/showrunner-schema/src/types/automations.ts

interface SubgraphDefinition {
  id: string
  name: string
  parameters: SubgraphParam[]
  outputs: SubgraphParam[]
  nodes: GraphNode[]          // the graph body
  edges: GraphEdge[]          // execution edges within the subgraph
  entryNodeId: string
}

interface SubgraphParam {
  name: string
  type: "string" | "number" | "boolean" | "array" | "object" | "any" | "color"
  default?: any
}

// Extended AutomationData
interface AutomationData {
  sequence: Sequence          // DEPRECATED — kept for migration
  floatingSequences: FloatingSequence[]
  dataWires?: AutomationDataWire[]
  variableNodes?: AutomationVariableNode[]
  testContext?: any
  // NEW:
  graph?: AutomationGraph     // new graph model (takes precedence over sequence)
  subgraphs?: SubgraphDefinition[]
}

interface AutomationGraph {
  nodes: GraphNode[]
  edges: GraphEdge[]
  entryNodeId: string
}

interface GraphNode {
  id: string
  type: "action" | "if" | "switch" | "for" | "forEach" | "while" | "break" | "continue" | "return" | "subgraphCall"
  data: any                   // type-specific payload (ActionInfo, IfNode, etc.)
  x: number
  y: number
}

interface GraphEdge {
  id: string
  from: string
  to: string
  port?: string               // "then" | "else" | "body" | "next" | "case:0" | default "out"
}
```

### Expression system

Small expression language for conditions and loop bounds. Compiled to a fast evaluator — NOT eval().

```typescript
type Expression =
  | { type: "literal"; value: any }
  | { type: "variable"; name: string }           // context/local var
  | { type: "port"; nodeId: string; port: string } // data wire reference
  | { type: "binary"; op: BinaryOp; left: Expression; right: Expression }
  | { type: "unary"; op: UnaryOp; operand: Expression }
  | { type: "member"; object: Expression; property: string }
  | { type: "index"; object: Expression; index: Expression }
  | { type: "call"; fn: BuiltinFn; args: Expression[] }

type BinaryOp = "==" | "!=" | ">" | "<" | ">=" | "<=" | "&&" | "||" | "+" | "-" | "*" | "/" | "%"
type UnaryOp = "!" | "-" | "typeof"
type BuiltinFn = "len" | "includes" | "startsWith" | "endsWith" | "toString" | "toNumber" | "toBoolean" | "floor" | "ceil" | "round" | "abs" | "min" | "max" | "keys" | "values" | "slice" | "concat"
```

## Compiler

`libs/showrunner-core/src/graph-engine/compiler.ts`

### Instruction set

```typescript
enum OpCode {
  EXEC,          // run action node, store result
  JUMP,          // unconditional goto
  JUMP_IF,       // conditional goto (pop condition from eval stack)
  JUMP_IF_NOT,   // conditional goto (inverted)
  EVAL,          // evaluate expression, push result to eval stack
  STORE,         // pop eval stack → local variable
  LOAD,          // push local variable → eval stack
  LOOP_INIT,     // initialize loop counter
  LOOP_CHECK,    // check loop condition, jump to exit if false
  LOOP_STEP,     // increment counter
  ITER_INIT,     // initialize forEach iterator
  ITER_NEXT,     // advance iterator, jump to exit if done
  CALL,          // push frame, jump to subgraph entry
  RET,           // pop frame, return to caller
  YIELD,         // yield control to event loop (inserted in long loops)
  HALT,          // end program
}

interface Instruction {
  op: OpCode
  nodeId?: string        // source node for debugging
  arg0?: number          // jump target / subgraph index
  arg1?: any             // literal / expression / variable name
  arg2?: any             // secondary operand
}
```

### Compilation algorithm

1. Topologically sort graph nodes starting from `entryNodeId`
2. For each node, emit instruction(s):
   - **action** → `EXEC`
   - **if** → `EVAL` condition + `JUMP_IF_NOT` to else label + then body + `JUMP` past else + else body
   - **for** → `LOOP_INIT` + label + `LOOP_CHECK` + body + `LOOP_STEP` + `JUMP` back + exit label
   - **forEach** → `ITER_INIT` + label + `ITER_NEXT` + body + `JUMP` back + exit label
   - **while** → label + `EVAL` condition + `JUMP_IF_NOT` exit + body + `JUMP` back + exit label
   - **break** → `JUMP` to enclosing loop exit
   - **continue** → `JUMP` to enclosing loop header
   - **subgraphCall** → evaluate inputs + `CALL`
   - **return** → evaluate outputs + `RET`
3. Insert `YIELD` every N instructions inside loops (configurable, default 64)
4. Resolve label positions to absolute instruction indices
5. Emit `HALT` at end

### Performance optimizations

- **Pre-allocated locals array** — variables stored by index not name at runtime
- **Expression pre-compilation** — expressions become small function objects (not re-parsed per eval)
- **Subgraph inlining** — small subgraphs (≤8 nodes) inlined at call sites to eliminate CALL/RET overhead
- **Dead code elimination** — unreachable nodes pruned during compilation
- **Wire resolution memoization** — data wire lookups compiled to direct array index references

## VM Runtime

`libs/showrunner-core/src/graph-engine/vm.ts`

```typescript
class GraphVM {
  private pc: number = 0
  private stack: any[] = []           // eval stack
  private locals: any[] = []          // local variables (pre-sized)
  private callStack: Frame[] = []     // subgraph call frames
  private loopStack: LoopState[] = [] // active loop states
  private abortSignal: AbortSignal
  private debugger?: SequenceDebugger
  private nodeResults: Map<string, Record<string, any>>
  private yieldCounter: number = 0

  async execute(program: Program, context: SequenceContext): Promise<"complete" | "aborted"> {
    while (this.pc < program.instructions.length) {
      if (this.abortSignal.aborted) return "aborted"
      const instr = program.instructions[this.pc]
      await this.step(instr)
      this.pc++
    }
    return "complete"
  }

  private async step(instr: Instruction) {
    switch (instr.op) {
      case OpCode.EXEC: return await this.execAction(instr)
      case OpCode.JUMP: this.pc = instr.arg0! - 1; break
      case OpCode.JUMP_IF: if (this.stack.pop()) this.pc = instr.arg0! - 1; break
      case OpCode.JUMP_IF_NOT: if (!this.stack.pop()) this.pc = instr.arg0! - 1; break
      case OpCode.EVAL: this.stack.push(this.evalExpr(instr.arg1)); break
      case OpCode.STORE: this.locals[instr.arg0!] = this.stack.pop(); break
      case OpCode.LOAD: this.stack.push(this.locals[instr.arg0!]); break
      case OpCode.YIELD: await this.yieldToEventLoop(); break
      case OpCode.CALL: this.pushFrame(instr); break
      case OpCode.RET: this.popFrame(); break
      case OpCode.HALT: this.pc = Infinity; break
      // ... loop ops
    }
  }

  private async yieldToEventLoop() {
    await new Promise(resolve => setImmediate(resolve))
  }
}
```

### Debug hooks

The VM calls the same `SequenceDebugger` interface used today:
- `EXEC` instruction → `debugger.markStart(nodeId)` before, `debugger.markEnd(nodeId)` after
- Action results → `debugger.logResult(nodeId, result)`
- Errors → `debugger.logError(nodeId, error)`
- Loop iterations → optional `debugger.markIteration(nodeId, index)` (new)
- Branch taken → optional `debugger.markBranch(nodeId, port)` (new)

UI sees all nodes light up in real-time, exactly as before.

## Implementation Phases

### Phase 1: Core Engine (no UI changes)

**Files:**
- `libs/showrunner-schema/src/types/graph.ts` — new types (GraphNode, GraphEdge, Expression, SubgraphDefinition)
- `libs/showrunner-schema/src/types/automations.ts` — add `graph?` and `subgraphs?` fields
- `libs/showrunner-core/src/graph-engine/compiler.ts` — GraphCompiler
- `libs/showrunner-core/src/graph-engine/vm.ts` — GraphVM
- `libs/showrunner-core/src/graph-engine/expression.ts` — expression evaluator
- `libs/showrunner-core/src/graph-engine/index.ts` — barrel export
- `libs/showrunner-core/src/graph-engine/__tests__/compiler.test.ts`
- `libs/showrunner-core/src/graph-engine/__tests__/vm.test.ts`
- `libs/showrunner-core/src/graph-engine/__tests__/expression.test.ts`

**Deliverable:** Engine compiles a graph and VM executes it, passing all unit tests. Existing SequenceRunner unchanged (backward compatible).

**Status:** ✅ Complete — 118 tests passing (75 expression, 19 compiler, 24 VM). Expression evaluator throws on division by zero, unknown operators, and unknown builtins. Compiler isolates loop variable scope for nested loops sharing the same variable name.

**Tests:** ≥50 tests covering:
- Linear execution, branching, nested branches
- For/forEach/while with break/continue
- Subgraph calls, recursive subgraphs (with depth limit)
- Expression evaluation (all operators)
- Data wire resolution
- Abort mid-execution
- Yield behavior in tight loops
- Error propagation

### Phase 2: Migration Bridge

**Files:**
- `libs/showrunner-core/src/graph-engine/migration.ts` — converts old `Sequence` → `AutomationGraph`
- `libs/showrunner-core/src/queue-system/action-queue.ts` — use GraphVM when `automation.graph` present, fall back to SequenceRunner

**Deliverable:** Existing automations work unchanged. New graph-based automations use the VM. Both paths debuggable.

### Phase 3: Control Flow Nodes (UI)

**Files:**
- `packages/showrunner/src/renderer/components/automation/nodes/IfNode.vue`
- `packages/showrunner/src/renderer/components/automation/nodes/ForLoopNode.vue`
- `packages/showrunner/src/renderer/components/automation/nodes/ForEachNode.vue`
- `packages/showrunner/src/renderer/components/automation/nodes/WhileNode.vue`
- `packages/showrunner/src/renderer/components/automation/nodes/SwitchNode.vue`
- `packages/showrunner/src/renderer/components/automation/ExpressionEditor.vue`
- `packages/showrunner/src/renderer/components/automation/NodeAutomationEdit.vue` — register new node types in context menu, rendering, and graph serialization

**Deliverable:** Users can add If, Switch, For, ForEach, While nodes to the canvas. Execution edges visually show which branch was taken.

### Phase 4: Subgraphs (UI + Runtime)

**Files:**
- `packages/showrunner/src/renderer/components/automation/SubgraphEditor.vue`
- `packages/showrunner/src/renderer/components/automation/nodes/SubgraphCallNode.vue`
- Context menu: "Create Subgraph" (from selection) and "Call Subgraph"
- Subgraph parameter editor panel

**Deliverable:** Users define reusable subgraphs with typed inputs/outputs and call them from any automation. Recursion supported with configurable depth limit.

### Phase 5: Execution Edges (Directed Graph)

**Files:**
- `packages/showrunner/src/renderer/components/automation/NodeAutomationEdit.vue` — re-enable edges as user-drawn execution connections (not auto-generated from array)
- Edge drawing: drag from output port to input port
- Edge validation: no cycles except inside loops, single entry per non-merge node

**Deliverable:** The graph is truly user-defined. Nodes execute in the order defined by execution edges, not array position.

### Phase 6: Polish & Performance

- Expression autocomplete (variable names, port references)
- Loop performance profiling badge (shows iteration count + time)
- Subgraph folding (collapse subgraph call to single node in parent)
- Compile-time warnings (infinite loop risk, unreachable nodes)
- Import/export subgraphs between automations

## Performance Budget

| Metric | Target |
|--------|--------|
| Compile time (100-node graph) | < 2ms |
| VM instruction throughput | > 100k instr/sec |
| Memory per execution | < 50KB baseline |
| Yield interval | every 64 ops in loops |
| Max loop iterations | 10,000 default (configurable) |
| Max recursion depth | 32 default (configurable) |
| Recompile trigger | on graph model change only |

## Safety

- **Infinite loop protection** — `maxIterations` on every loop (default 10000), VM aborts and reports error
- **Recursion depth limit** — call stack depth capped at 32 by default
- **Yield to event loop** — prevents UI/IPC freeze during heavy computation
- **Abort signal** — all execution respects AbortController, can be cancelled at any instruction
- **Type coercion** — expression evaluator uses strict equality by default, no implicit `eval()`
- **No user code execution** — expressions are a safe DSL, not JavaScript

## Migration Strategy

1. New automations default to graph mode
2. Existing automations keep working via SequenceRunner
3. One-click "Upgrade to Graph" converts old sequence → graph (irreversible but with backup)
4. After transition period, SequenceRunner becomes deprecated
