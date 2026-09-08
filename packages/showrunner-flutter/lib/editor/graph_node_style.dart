import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';

/// Colors and geometry from main's NodeAutomationNodeCard.vue.
NodeStyle graphNodeStyle(
  NodeState state,
  Color accent, {
  bool trigger = false,
}) => NodeStyle(
  decoration: BoxDecoration(
    color: trigger ? const Color(0xff40256c) : const Color(0xff151515),
    border: Border.all(
      color: state.isSelected ? const Color(0xffffdf6b) : accent,
      width: 2,
    ),
    borderRadius: BorderRadius.circular(6),
    boxShadow: [
      if (state.isSelected)
        const BoxShadow(color: Color(0x33ffdf6b), spreadRadius: 3),
      BoxShadow(
        color: state.isSelected
            ? const Color(0x59000000)
            : const Color(0x47000000),
        offset: Offset(0, state.isSelected ? 12 : 10),
        blurRadius: state.isSelected ? 28 : 24,
      ),
    ],
  ),
);
