import '../../schema/automation.dart';

final class AutomationStarter {
  const AutomationStarter({
    required this.id,
    required this.name,
    required this.description,
    required this.automation,
  });

  final String id;
  final String name;
  final String description;
  final AutomationData automation;
}

List<AutomationStarter> defaultAutomationStarters() => [
  _starter(
    id: 'chat-to-queue',
    name: 'Chat message to queue',
    description: 'Queue a message whenever a chat event arrives.',
    nodes: const [
      GraphNode(id: 'trigger', type: 'trigger.chatMessage', x: -300, y: 0),
      GraphNode(id: 'queue', type: 'queue.addItem', x: 0, y: 0),
    ],
    edges: const [
      GraphEdge(
        id: 'trigger-queue',
        from: 'trigger',
        to: 'queue',
        port: 'completed',
      ),
    ],
  ),
  _starter(
    id: 'chat-overlay',
    name: 'Chat message overlay',
    description: 'Display a chat message as an overlay event.',
    nodes: const [
      GraphNode(id: 'trigger', type: 'trigger.chatMessage', x: -300, y: 0),
      GraphNode(id: 'overlay', type: 'overlay.pushChat', x: 0, y: 0),
    ],
    edges: const [
      GraphEdge(
        id: 'trigger-overlay',
        from: 'trigger',
        to: 'overlay',
        port: 'completed',
      ),
    ],
  ),
  _starter(
    id: 'chat-queue-overlay',
    name: 'Chat queue and overlay',
    description:
        'Queue a chat event and show the completed item as an overlay.',
    nodes: const [
      GraphNode(id: 'trigger', type: 'trigger.chatMessage', x: -420, y: 0),
      GraphNode(id: 'queue', type: 'queue.addItem', x: -100, y: 0),
      GraphNode(id: 'overlay', type: 'overlay.pushChat', x: 220, y: 0),
    ],
    edges: const [
      GraphEdge(
        id: 'trigger-queue',
        from: 'trigger',
        to: 'queue',
        port: 'completed',
      ),
      GraphEdge(
        id: 'queue-overlay',
        from: 'queue',
        to: 'overlay',
        port: 'completed',
      ),
    ],
  ),
  _starter(
    id: 'paid-alert-to-queue',
    name: 'Subscription alert to queue',
    description:
        'Queue a Twitch subscription event for a non-overlapping alert.',
    nodes: const [
      GraphNode(
        id: 'trigger',
        type: 'trigger.twitch.subscription',
        x: -420,
        y: 0,
      ),
      GraphNode(id: 'queue', type: 'queue.addItem', x: -100, y: 0),
      GraphNode(id: 'overlay', type: 'overlay.pushChat', x: 220, y: 0),
    ],
    edges: const [
      GraphEdge(
        id: 'trigger-queue',
        from: 'trigger',
        to: 'queue',
        port: 'completed',
      ),
      GraphEdge(
        id: 'queue-overlay',
        from: 'queue',
        to: 'overlay',
        port: 'completed',
      ),
    ],
  ),
  _starter(
    id: 'scene-banner',
    name: 'Chat scene banner',
    description: 'Queue a chat event, switch OBS scene, then show a banner.',
    nodes: const [
      GraphNode(id: 'trigger', type: 'trigger.twitch.chat', x: -560, y: 0),
      GraphNode(id: 'queue', type: 'queue.addItem', x: -280, y: 0),
      GraphNode(
        id: 'scene',
        type: 'action',
        x: 20,
        y: 0,
        data: {
          'plugin': 'obs',
          'action': 'scene',
          'config': {'scene': 'Starting soon'},
        },
      ),
      GraphNode(id: 'overlay', type: 'overlay.pushChat', x: 320, y: 0),
    ],
    edges: const [
      GraphEdge(
        id: 'trigger-queue',
        from: 'trigger',
        to: 'queue',
        port: 'completed',
      ),
      GraphEdge(id: 'queue-scene', from: 'queue', to: 'scene'),
      GraphEdge(id: 'scene-overlay', from: 'scene', to: 'overlay'),
    ],
  ),
  _starter(
    id: 'obs-scene-change',
    name: 'Chat command to OBS scene',
    description: 'Use a chat event to change the configured OBS scene.',
    nodes: const [
      GraphNode(id: 'trigger', type: 'trigger.twitch.chat', x: -300, y: 0),
      GraphNode(
        id: 'scene',
        type: 'action',
        x: 0,
        y: 0,
        data: {
          'plugin': 'obs',
          'action': 'scene',
          'config': {'scene': 'Starting soon'},
        },
      ),
    ],
    edges: const [
      GraphEdge(
        id: 'trigger-scene',
        from: 'trigger',
        to: 'scene',
        port: 'completed',
      ),
    ],
  ),
];

AutomationStarter _starter({
  required String id,
  required String name,
  required String description,
  required List<GraphNode> nodes,
  required List<GraphEdge> edges,
}) => AutomationStarter(
  id: id,
  name: name,
  description: description,
  automation: AutomationData(
    graph: AutomationGraph(
      nodes: nodes,
      edges: edges,
      entryNodeId: nodes.first.id,
    ),
    extra: {'name': name},
  ),
);
