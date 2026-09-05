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

/// Product starter templates from the reference application.
///
/// A starter contains ordinary V2 action nodes and data wires. The selected
/// trigger is kept as document metadata so it can be used when the resource
/// is attached to a profile, while the graph itself remains reusable.
List<AutomationStarter> defaultAutomationStarters() => [
  _template(
    id: 'youtube-paid-alert',
    name: 'YouTube Paid Alert',
    description: 'Super Chat or Super Sticker -> Paid Alert widget.',
    plugin: 'youtube',
    trigger: 'superChat',
    nodes: [
      _action('push-paid-alert', 'overlays', 'pushPaidAlert', 360, 120, {
        'eventId': '',
        'platform': 'youtube',
        'viewerName': '',
        'amount': '',
        'currency': 'USD',
        'title': 'New Super Chat',
        'message': '',
      }),
    ],
    dataWires: _triggerWires('push-paid-alert', {
      'messageId': 'eventId',
      'viewerName': 'viewerName',
      'amountMicros': 'amount',
      'currency': 'currency',
      'message': 'message',
    }),
  ),
  _template(
    id: 'twitch-sub-paid-alert',
    name: 'Twitch Sub Alert',
    description: 'Subscription -> Paid Alert widget.',
    plugin: 'twitch',
    trigger: 'subscription',
    nodes: [
      _action('push-paid-alert', 'overlays', 'pushPaidAlert', 360, 120, {
        'eventId': 'twitch-sub-{{ viewer }}-{{ totalMonths }}',
        'platform': 'twitch',
        'viewerName': '',
        'amount': '',
        'currency': '',
        'title': 'New Subscriber',
        'message': '',
      }),
    ],
    dataWires: _triggerWires('push-paid-alert', {
      'viewer': 'viewerName',
      'totalMonths': 'amount',
      'message': 'message',
    }),
  ),
  _template(
    id: 'twitch-bits-paid-alert',
    name: 'Twitch Bits Alert',
    description: 'Bits cheered -> Paid Alert widget.',
    plugin: 'twitch',
    trigger: 'bits',
    nodes: [
      _action('push-paid-alert', 'overlays', 'pushPaidAlert', 360, 120, {
        'eventId': 'twitch-bits-{{ viewer }}-{{ bits }}',
        'platform': 'twitch',
        'viewerName': '',
        'amount': '',
        'currency': 'bits',
        'title': 'Bits Cheered',
        'message': '',
      }),
    ],
    dataWires: _triggerWires('push-paid-alert', {
      'viewer': 'viewerName',
      'bits': 'amount',
      'message': 'message',
    }),
  ),
  _template(
    id: 'starting-soon-scene-banner',
    name: 'Starting Soon Scene Banner',
    description: 'Starter graph that publishes a scene.begin banner.',
    plugin: 'ShowRunner',
    trigger: 'autoRun',
    nodes: [
      _action('begin-scene', 'overlays', 'beginSceneOverlay', 360, 120, {
        'sceneKey': 'starting-soon',
        'title': 'Starting Soon',
        'subtitle': 'Stream begins shortly',
        'accentColor': '#9146ff',
      }),
    ],
  ),
  _template(
    id: 'obs-scene-change',
    name: 'OBS Scene Change',
    description: 'Manual starter that changes the current OBS scene.',
    plugin: 'ShowRunner',
    trigger: 'autoRun',
    nodes: [
      _action('change-scene', 'obs', 'scene', 360, 120, {
        'obs': null,
        'scene': '',
      }),
    ],
  ),
  _template(
    id: 'twitch-chat-command-reply',
    name: 'Twitch Chat Command Reply',
    description: 'Chat command -> send a chat response.',
    plugin: 'twitch',
    trigger: 'chat',
    triggerConfig: {
      'command': {
        'mode': 'command',
        'match': '!hello',
        'arguments': [],
        'hasMessage': false,
      },
      'cooldown': null,
      'group': <String, dynamic>{},
    },
    nodes: [
      _action('send-chat-reply', 'twitch', 'chat', 360, 120, {
        'message': 'Hey {{ viewerName }}, thanks for using the command!',
      }),
    ],
  ),
  _template(
    id: 'twitch-chat-moderation-review',
    name: 'Twitch Chat Moderation Review',
    description: 'Chat command context -> moderation docker filter action.',
    plugin: 'twitch',
    trigger: 'chat',
    triggerConfig: {
      'command': {
        'mode': 'command',
        'match': '!moderate',
        'arguments': [],
        'hasMessage': true,
      },
      'cooldown': null,
      'group': <String, dynamic>{},
    },
    nodes: [
      _action('moderate-chat', 'moderation', 'moderateChatMessage', 360, 120, {
        'platform': '',
        'messageId': '',
        'viewerId': '',
        'viewerName': '',
        'message': '',
        'badges': '',
        'isModerator': false,
        'isMember': false,
        'isOwner': false,
      }),
    ],
    dataWires: _triggerWires('moderate-chat', {
      'platform': 'platform',
      'messageId': 'messageId',
      'viewerId': 'viewerId',
      'viewerName': 'viewerName',
      'message': 'message',
      'badges': 'badges',
    }),
  ),
  _template(
    id: 'stream-plan-next-segment',
    name: 'Stream Plan Next Segment',
    description: 'Manual starter that advances the active stream plan.',
    plugin: 'ShowRunner',
    trigger: 'autoRun',
    nodes: [
      _action(
        'next-stream-plan-segment',
        'stream-plans',
        'nextSegment',
        360,
        120,
        const {},
      ),
    ],
  ),
  _template(
    id: 'ending-scene-banner',
    name: 'Ending Scene Banner',
    description:
        'Starter graph that publishes a scene.end banner after a closing message.',
    plugin: 'ShowRunner',
    trigger: 'autoRun',
    nodes: [
      _action('begin-scene', 'overlays', 'beginSceneOverlay', 360, 120, {
        'sceneKey': 'ending',
        'title': 'Thanks for watching',
        'subtitle': 'See you next stream',
        'accentColor': '#64b5f6',
      }),
      _action('end-scene', 'overlays', 'endSceneOverlay', 640, 120, {
        'sceneKey': 'ending',
      }),
    ],
  ),
  _template(
    id: 'youtube-paid-event-alerts-queue',
    name: 'Paid Event -> Add to Alerts Queue',
    description:
        'Super Chat -> Add to Queue for a paid alert worker automation.',
    plugin: 'youtube',
    trigger: 'superChat',
    nodes: [
      _action('queue-paid-alert', 'ShowRunner', 'addToQueue', 360, 120, {
        'queue': null,
        'automation': null,
        'payload': {
          'eventId': '{{ messageId }}',
          'platform': 'youtube',
          'viewerName': '{{ viewerName }}',
          'amount': '{{ amountMicros }}',
          'currency': '{{ currency }}',
          'title': 'New Super Chat',
          'message': '{{ message }}',
        },
      }),
    ],
  ),
  _template(
    id: 'paid-alert-queue-worker',
    name: 'Queue Item Started -> Paid Alert Overlay -> Sound -> Complete',
    description: 'Queue worker graph for paid alerts with optional sound.',
    plugin: 'ShowRunner',
    trigger: 'queueItemStarted',
    nodes: [
      _action('push-paid-alert', 'overlays', 'pushPaidAlert', 360, 120, {
        'targetWidget': null,
        'eventId': '{{ payload.eventId }}',
        'platform': '{{ payload.platform }}',
        'viewerName': '{{ payload.viewerName }}',
        'amount': '{{ payload.amount }}',
        'currency': '{{ payload.currency }}',
        'title': '{{ payload.title }}',
        'message': '{{ payload.message }}',
      }),
      _action('play-alert-sound', 'sound', 'sound', 640, 120, {
        'output': null,
        'sound': '',
        'volume': 100,
        'startTime': 0,
      }),
      _action(
        'complete-paid-alert',
        'ShowRunner',
        'completeQueueItem',
        920,
        120,
        const {},
      ),
    ],
  ),
  _template(
    id: 'scene-begin-scene-queue',
    name: 'Scene Begin -> Add to Scene Queue',
    description:
        'Scene start event -> Add to Queue for a scene worker automation.',
    plugin: 'ShowRunner',
    trigger: 'autoRun',
    nodes: [
      _action('queue-scene-banner', 'ShowRunner', 'addToQueue', 360, 120, {
        'queue': null,
        'automation': null,
        'payload': {
          'sceneKey': 'starting-soon',
          'title': 'Starting Soon',
          'subtitle': 'Stream begins shortly',
          'accentColor': '#9146ff',
        },
      }),
    ],
  ),
  _template(
    id: 'scene-banner-queue-worker',
    name: 'Queue Item Started -> Scene Banner -> Shader Layer -> Complete',
    description:
        'Queue worker graph for scene banners with an optional shader layer.',
    plugin: 'ShowRunner',
    trigger: 'queueItemStarted',
    nodes: [
      _action('begin-scene-banner', 'overlays', 'beginSceneOverlay', 360, 120, {
        'targetWidget': null,
        'sceneKey': '{{ payload.sceneKey }}',
        'title': '{{ payload.title }}',
        'subtitle': '{{ payload.subtitle }}',
        'accentColor': '{{ payload.accentColor }}',
      }),
      _action('show-shader-layer', 'overlays', 'widgetVisibility', 640, 120, {
        'widget': null,
        'enabled': true,
      }),
      _action(
        'complete-scene-banner',
        'ShowRunner',
        'completeQueueItem',
        920,
        120,
        const {},
      ),
    ],
  ),
];

AutomationStarter _template({
  required String id,
  required String name,
  required String description,
  required String plugin,
  required String trigger,
  required List<GraphNode> nodes,
  List<GraphEdge>? edges,
  List<DataWire> dataWires = const <DataWire>[],
  JsonMap triggerConfig = const <String, dynamic>{},
}) {
  final graphEdges = edges ?? _sequentialEdges(nodes);
  return AutomationStarter(
    id: id,
    name: name,
    description: description,
    automation: AutomationData(
      graph: AutomationGraph(
        nodes: nodes,
        edges: graphEdges,
        entryNodeId: nodes.first.id,
      ),
      dataWires: dataWires,
      extra: {
        'name': name,
        'plugin': plugin,
        'trigger': trigger,
        'config': triggerConfig,
        'stop': false,
      },
    ),
  );
}

GraphNode _action(
  String id,
  String plugin,
  String action,
  double x,
  double y,
  JsonMap config,
) => GraphNode(
  id: id,
  type: 'action',
  x: x,
  y: y,
  data: {'plugin': plugin, 'action': action, 'config': config},
);

List<GraphEdge> _sequentialEdges(List<GraphNode> nodes) => [
  for (var index = 0; index < nodes.length - 1; index++)
    GraphEdge(
      id: '${nodes[index].id}:${nodes[index + 1].id}',
      from: nodes[index].id,
      to: nodes[index + 1].id,
    ),
];

List<DataWire> _triggerWires(String toNode, Map<String, String> ports) => [
  for (final entry in ports.entries)
    DataWire(
      id: 'trigger:${entry.key}->$toNode:${entry.value}',
      fromNode: 'trigger',
      fromPort: entry.key,
      toNode: toNode,
      toPort: entry.value,
    ),
];
