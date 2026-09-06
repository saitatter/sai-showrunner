# ADR-002: Keep Flutter graph-only for automation editing

Status: accepted

## Context

The `main` README describes a Timeline mode, but the frozen renderer source
contains no Timeline editor implementation or Timeline-specific persistence
contract. The renderer's automation page routes to the node editor, while the
remaining Timeline references are theme styles and branding assets.

Flutter already provides the supported automation workflow through the graph
editor, including control flow, data wires, variables, queues, subgraphs,
debugger feedback, save/close behavior and runtime execution.

## Decision

Do not add a separate Timeline editor to the Flutter replacement candidate.
Automation editing remains graph-only. The unsupported Timeline label is not
carried into the Flutter shell, and no Timeline-specific data is synthesized
or converted by the strict V2 repositories.

## Consequences

- There is one automation editing model and one runtime contract.
- No second editor or persistence format is introduced for a surface that is
  not implemented in the frozen reference renderer.
- Graph editor parity, runtime fixtures and visual proof remain required.
- If a real Timeline implementation is added to `main`, it must be treated as
  a new product requirement with its own contract and decision review.

## Rejected alternative

Porting a Timeline editor based only on README wording would add an unverified
workflow and a second persistence model without a source implementation to
compare against.
