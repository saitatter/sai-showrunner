import '../../../components/data_inputs/data_input.dart';

class OverlayWidgetDefinition {
  const OverlayWidgetDefinition({
    required this.plugin,
    required this.widget,
    required this.name,
    required this.width,
    required this.height,
    required this.configSchema,
  });

  final String plugin;
  final String widget;
  final String name;
  final int width;
  final int height;
  final DartDataInputSchema configSchema;

  Map<String, dynamic> defaultConfig() => Map<String, dynamic>.from(
    constructDartDataInputDefault(configSchema) as Map,
  );

  Map<String, dynamic> createWidget({String? id}) => {
    'id': id ?? 'widget-${DateTime.now().microsecondsSinceEpoch}',
    'plugin': plugin,
    'widget': widget,
    'name': name,
    'size': {'width': width, 'height': height},
    'position': {'x': 0, 'y': 0},
    'config': defaultConfig(),
    'visible': true,
    'locked': false,
  };
}

const _labelConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'message',
      label: 'Text',
      kind: DartDataInputKind.multilineText,
      required: true,
      defaultValue: 'Label',
      multiline: true,
    ),
  ],
);

const _chatFeedConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'fontFamily',
      label: 'Font Family',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Inter, Arial, sans-serif',
    ),
    DartDataInputSchema(
      key: 'fontSize',
      label: 'Font Size',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 24,
    ),
    DartDataInputSchema(
      key: 'backgroundColor',
      label: 'Background Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#0d1117',
    ),
    DartDataInputSchema(
      key: 'backgroundOpacity',
      label: 'Background Opacity',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.72,
    ),
    DartDataInputSchema(
      key: 'fadeTime',
      label: 'Fade Time Seconds',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 10,
    ),
    DartDataInputSchema(
      key: 'maxMessages',
      label: 'Max Messages',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 8,
    ),
    DartDataInputSchema(
      key: 'orientation',
      label: 'Layout',
      kind: DartDataInputKind.enumeration,
      required: true,
      options: ['horizontal', 'vertical'],
      defaultValue: 'horizontal',
    ),
    DartDataInputSchema(
      key: 'twitchColor',
      label: 'Twitch Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#9146ff',
    ),
    DartDataInputSchema(
      key: 'youtubeColor',
      label: 'YouTube Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#ff0033',
    ),
    DartDataInputSchema(
      key: 'showBadges',
      label: 'Show Badges',
      kind: DartDataInputKind.boolean,
      required: true,
      defaultValue: true,
    ),
  ],
);

const _paidAlertConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'fontFamily',
      label: 'Font Family',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Inter, Arial, sans-serif',
    ),
    DartDataInputSchema(
      key: 'accentColor',
      label: 'Accent Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#ffd166',
    ),
    DartDataInputSchema(
      key: 'backgroundColor',
      label: 'Background Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#131313',
    ),
    DartDataInputSchema(
      key: 'backgroundOpacity',
      label: 'Background Opacity',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.86,
    ),
    DartDataInputSchema(
      key: 'duration',
      label: 'Duration Seconds',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 7,
    ),
    DartDataInputSchema(
      key: 'previewTitle',
      label: 'Preview Title',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Super Chat',
    ),
    DartDataInputSchema(
      key: 'previewViewer',
      label: 'Preview Viewer',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Supporter',
    ),
    DartDataInputSchema(
      key: 'previewMessage',
      label: 'Preview Message',
      kind: DartDataInputKind.multilineText,
      required: true,
      defaultValue: 'Thanks for the stream!',
      multiline: true,
    ),
    DartDataInputSchema(
      key: 'previewAmount',
      label: 'Preview Amount',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: '10.00',
    ),
    DartDataInputSchema(
      key: 'previewCurrency',
      label: 'Preview Currency',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'USD',
    ),
  ],
);

const _sceneBannerConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'fontFamily',
      label: 'Font Family',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Inter, Arial, sans-serif',
    ),
    DartDataInputSchema(
      key: 'accentColor',
      label: 'Accent Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#9146ff',
    ),
    DartDataInputSchema(
      key: 'backgroundColor',
      label: 'Background Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#101010',
    ),
    DartDataInputSchema(
      key: 'backgroundOpacity',
      label: 'Background Opacity',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.82,
    ),
    DartDataInputSchema(
      key: 'duration',
      label: 'Duration Seconds',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 6,
    ),
    DartDataInputSchema(
      key: 'previewTitle',
      label: 'Preview Title',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Starting Soon',
    ),
    DartDataInputSchema(
      key: 'previewSubtitle',
      label: 'Preview Subtitle',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Scene automation preview',
    ),
  ],
);

const _shaderLayerConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'preset',
      label: 'Shader Preset',
      kind: DartDataInputKind.enumeration,
      required: true,
      options: [
        'aurora',
        'grid',
        'plasma',
        'nebula',
        'scanlines',
        'vortex',
        'custom',
      ],
      defaultValue: 'aurora',
    ),
    DartDataInputSchema(
      key: 'customFragmentShader',
      label: 'Custom Fragment Shader',
      kind: DartDataInputKind.multilineText,
      multiline: true,
      defaultValue: '',
    ),
    DartDataInputSchema(
      key: 'accentColor',
      label: 'Accent Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#9146ff',
    ),
    DartDataInputSchema(
      key: 'secondaryColor',
      label: 'Secondary Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#00d1ff',
    ),
    DartDataInputSchema(
      key: 'intensity',
      label: 'Intensity',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.8,
    ),
    DartDataInputSchema(
      key: 'speed',
      label: 'Speed',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 1,
    ),
    DartDataInputSchema(
      key: 'opacity',
      label: 'Opacity',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 1,
    ),
    DartDataInputSchema(
      key: 'blendMode',
      label: 'Blend Mode',
      kind: DartDataInputKind.enumeration,
      required: true,
      options: ['normal', 'screen', 'overlay', 'lighten', 'multiply'],
      defaultValue: 'normal',
    ),
    DartDataInputSchema(
      key: 'text',
      label: 'Text',
      kind: DartDataInputKind.text,
      defaultValue: '',
    ),
    DartDataInputSchema(
      key: 'shaderGraph',
      label: 'Shader Graph (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'shaderUniforms',
      label: 'Shader Uniforms (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'shaderUniformBindings',
      label: 'Shader Uniform Bindings (JSON)',
      kind: DartDataInputKind.object,
    ),
  ],
);

const _barConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'value',
      label: 'Value',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 25,
    ),
    DartDataInputSchema(
      key: 'target',
      label: 'Target',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 100,
    ),
    DartDataInputSchema(
      key: 'direction',
      label: 'Direction',
      kind: DartDataInputKind.enumeration,
      required: true,
      options: ['Right', 'Left', 'Up', 'Down'],
      defaultValue: 'Right',
    ),
    DartDataInputSchema(
      key: 'outerRadius',
      label: 'Outer Corners (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'backgroundStyle',
      label: 'Background Style (JSON)',
      kind: DartDataInputKind.object,
      defaultValue: <String, dynamic>{'color': '#FF0000', 'elements': []},
    ),
    DartDataInputSchema(
      key: 'outline',
      label: 'Outline (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'fillStyle',
      label: 'Fill Style (JSON)',
      kind: DartDataInputKind.object,
      defaultValue: <String, dynamic>{'color': '#00FF00', 'elements': []},
    ),
    DartDataInputSchema(
      key: 'fillLine',
      label: 'Fill Line (JSON)',
      kind: DartDataInputKind.object,
    ),
  ],
);

const _alertConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'media',
      label: 'Alert Media',
      kind: DartDataInputKind.array,
      itemKind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'textBelowMedia',
      label: 'Text Below Media',
      kind: DartDataInputKind.boolean,
      required: true,
      defaultValue: true,
    ),
    DartDataInputSchema(
      key: 'transition',
      label: 'Transition (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'title',
      label: 'Title Style (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'subtitle',
      label: 'Subtitle Style (JSON)',
      kind: DartDataInputKind.object,
    ),
  ],
);

const _leaderboardConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'sortBy',
      label: 'Sort By Viewer Variable',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      key: 'sortOrder',
      label: 'Sort Order (1 or -1)',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: -1,
    ),
    DartDataInputSchema(
      key: 'count',
      label: 'Count',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 10,
    ),
    DartDataInputSchema(
      key: 'variables',
      label: 'Display Variables',
      kind: DartDataInputKind.array,
      itemKind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'nameFont',
      label: 'Name Font (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'nameTextAlign',
      label: 'Name Alignment (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'nameBackground',
      label: 'Name Background (JSON)',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      key: 'nameBlock',
      label: 'Name Block (JSON)',
      kind: DartDataInputKind.object,
    ),
  ],
);

const _emoteBouncerConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'lifeTime',
      label: 'Emote Life Time (JSON range)',
      kind: DartDataInputKind.object,
      defaultValue: <String, dynamic>{'min': 7, 'max': 7},
    ),
    DartDataInputSchema(
      key: 'emoteSize',
      label: 'Emote Size (JSON range)',
      kind: DartDataInputKind.object,
      defaultValue: <String, dynamic>{'min': 80, 'max': 80},
    ),
    DartDataInputSchema(
      key: 'velocityMax',
      label: 'Launch Velocity Max',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.4,
    ),
    DartDataInputSchema(
      key: 'shakeTime',
      label: 'Time Between Shakes',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 5,
    ),
    DartDataInputSchema(
      key: 'shakeStrength',
      label: 'Shake Strength',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 1,
    ),
    DartDataInputSchema(
      key: 'gravityXScale',
      label: 'Gravity X Scale',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0,
    ),
    DartDataInputSchema(
      key: 'gravityYScale',
      label: 'Gravity Y Scale',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 1,
    ),
    DartDataInputSchema(
      key: 'spamPrevention',
      label: 'Spam Prevention',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          key: 'emoteRatio',
          label: 'Emote Ratio',
          kind: DartDataInputKind.number,
          required: true,
          defaultValue: 1,
        ),
        DartDataInputSchema(
          key: 'emoteCap',
          label: 'Total Emote Cap',
          kind: DartDataInputKind.number,
        ),
        DartDataInputSchema(
          key: 'emoteCapPerMessage',
          label: 'Max Emotes per Message',
          kind: DartDataInputKind.number,
        ),
      ],
    ),
    DartDataInputSchema(
      key: 'launchers',
      label: 'Launchers',
      kind: DartDataInputKind.array,
      itemKind: DartDataInputKind.object,
    ),
  ],
);

const overlayWidgetDefinitions = <OverlayWidgetDefinition>[
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'label',
    name: 'Label',
    width: 300,
    height: 200,
    configSchema: _labelConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'chatFeed',
    name: 'Chat Feed',
    width: 900,
    height: 180,
    configSchema: _chatFeedConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'paidAlert',
    name: 'Paid Alert',
    width: 680,
    height: 190,
    configSchema: _paidAlertConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'sceneBanner',
    name: 'Scene Banner',
    width: 900,
    height: 170,
    configSchema: _sceneBannerConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'shaderLayer',
    name: 'Shader Layer',
    width: 900,
    height: 500,
    configSchema: _shaderLayerConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'bar',
    name: 'Bar',
    width: 400,
    height: 90,
    configSchema: _barConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'alert',
    name: 'Alert',
    width: 300,
    height: 200,
    configSchema: _alertConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'leaderboard',
    name: 'Leader Board',
    width: 300,
    height: 500,
    configSchema: _leaderboardConfig,
  ),
  OverlayWidgetDefinition(
    plugin: 'overlays',
    widget: 'emote-bounce',
    name: 'Emote Bouncer',
    width: 1920,
    height: 1080,
    configSchema: _emoteBouncerConfig,
  ),
];

OverlayWidgetDefinition? findOverlayWidgetDefinition(
  String plugin,
  String widget,
) {
  for (final definition in overlayWidgetDefinitions) {
    if (definition.plugin == plugin && definition.widget == widget) {
      return definition;
    }
  }
  return null;
}
