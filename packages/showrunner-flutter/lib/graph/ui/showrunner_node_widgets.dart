import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart' show GraphNodeViewModel;
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../definitions/showrunner_graph_types.dart';

Widget showrunnerNodeHeader(BuildContext context, GraphNodeViewModel node) =>
    Row(
      children: [
        Icon(
          switch (automationNodeKind(node.node.type)) {
            'trigger' => Icons.bolt,
            'if' || 'switch' => Icons.call_split,
            'for' || 'forEach' || 'while' => Icons.loop,
            'variable' => Icons.data_object,
            'subgraphCall' => Icons.account_tree_outlined,
            'parameter' => Icons.input,
            'return' => Icons.keyboard_return,
            'break' || 'continue' => Icons.alt_route,
            _ => Icons.extension_outlined,
          },
          size: 16,
          color: Color(node.style.color),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            node.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xfff0eafa),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

Widget showrunnerPortLabel(
  BuildContext context,
  GraphNodeViewModel node,
  ResolvedPort port,
) {
  final output = port.direction == GraphPortDirection.output;
  return Tooltip(
    message: port.kind == GraphPortKind.control
        ? port.label
        : '${port.label} · ${port.dataType}',
    child: Row(
      mainAxisAlignment: output
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            port.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: output ? TextAlign.right : TextAlign.left,
            style: const TextStyle(color: Color(0xffc9c0d8), fontSize: 11),
          ),
        ),
        if (port.kind == GraphPortKind.data) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xffb78af2).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(switch (port.dataType) {
              'core.string' => 'str',
              'core.number' => 'num',
              'core.boolean' => 'bool',
              'core.object' => 'obj',
              'core.array' => 'arr',
              'core.any' => 'any',
              'showrunner.resource' => 'res',
              _ => port.dataType.split('.').last,
            }, style: const TextStyle(color: Color(0xffbca3da), fontSize: 9)),
          ),
        ],
      ],
    ),
  );
}
