import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class OverlayTarget {
  const OverlayTarget({this.widgetId, this.overlayId});

  factory OverlayTarget.fromRuntime(Object? value) {
    if (value is! Map) return const OverlayTarget();
    return OverlayTarget(
      widgetId: _string(value['widgetId']),
      overlayId: _string(value['overlayId']),
    );
  }

  final String? widgetId;
  final String? overlayId;

  bool get isValid =>
      widgetId?.trim().isNotEmpty == true &&
      overlayId?.trim().isNotEmpty == true;

  RuntimeMap toRuntime() => {
    if (widgetId != null) 'widgetId': widgetId,
    if (overlayId != null) 'overlayId': overlayId,
  };
}

OverlayTarget? overlayTargetFromRuntime(Object? value) {
  final target = OverlayTarget.fromRuntime(value);
  return target.isValid ? target : null;
}

final class OverlayTriggerWidgetConfig {
  const OverlayTriggerWidgetConfig({
    this.widgetId,
    this.overlayId,
    this.payload,
  });

  factory OverlayTriggerWidgetConfig.fromRuntime(RuntimeMap value) =>
      OverlayTriggerWidgetConfig(
        widgetId: _string(value['widgetId']),
        overlayId: _string(value['overlayId']),
        payload: _mapOrNull(value['payload']),
      );

  final String? widgetId;
  final String? overlayId;
  final RuntimeMap? payload;

  RuntimeMap toRuntime() => {
    if (widgetId != null) 'widgetId': widgetId,
    if (overlayId != null) 'overlayId': overlayId,
    if (payload != null) 'payload': payload,
  };
}

final class OverlayAlertConfig {
  const OverlayAlertConfig({this.alert, this.title, this.subtitle});

  factory OverlayAlertConfig.fromRuntime(RuntimeMap value) =>
      OverlayAlertConfig(
        alert: overlayTargetFromRuntime(value['alert']),
        title: _string(value['title']),
        subtitle: _string(value['subtitle']),
      );

  final OverlayTarget? alert;
  final String? title;
  final String? subtitle;

  RuntimeMap toRuntime() => {
    if (alert != null) 'alert': alert!.toRuntime(),
    if (title != null) 'title': title,
    if (subtitle != null) 'subtitle': subtitle,
  };
}

final class OverlayChatMessageConfig {
  const OverlayChatMessageConfig({
    this.targetWidget,
    this.messageId,
    this.platform,
    this.viewerName,
    this.message,
    this.badges,
  });

  factory OverlayChatMessageConfig.fromRuntime(RuntimeMap value) =>
      OverlayChatMessageConfig(
        targetWidget: overlayTargetFromRuntime(value['targetWidget']),
        messageId: _string(value['messageId']),
        platform: _string(value['platform']),
        viewerName: _string(value['viewerName']),
        message: _string(value['message']),
        badges: _string(value['badges']),
      );

  final OverlayTarget? targetWidget;
  final String? messageId;
  final String? platform;
  final String? viewerName;
  final String? message;
  final String? badges;

  RuntimeMap toRuntime() => {
    if (targetWidget != null) 'targetWidget': targetWidget!.toRuntime(),
    if (messageId != null) 'messageId': messageId,
    if (platform != null) 'platform': platform,
    if (viewerName != null) 'viewerName': viewerName,
    if (message != null) 'message': message,
    if (badges != null) 'badges': badges,
  };
}

final class OverlayPaidAlertConfig {
  const OverlayPaidAlertConfig({
    this.targetWidget,
    this.eventId,
    this.platform,
    this.viewerName,
    this.amount,
    this.currency,
    this.title,
    this.message,
  });

  factory OverlayPaidAlertConfig.fromRuntime(RuntimeMap value) =>
      OverlayPaidAlertConfig(
        targetWidget: overlayTargetFromRuntime(value['targetWidget']),
        eventId: _string(value['eventId']),
        platform: _string(value['platform']),
        viewerName: _string(value['viewerName']),
        amount: _string(value['amount']),
        currency: _string(value['currency']),
        title: _string(value['title']),
        message: _string(value['message']),
      );

  final OverlayTarget? targetWidget;
  final String? eventId;
  final String? platform;
  final String? viewerName;
  final String? amount;
  final String? currency;
  final String? title;
  final String? message;

  RuntimeMap toRuntime() => {
    if (targetWidget != null) 'targetWidget': targetWidget!.toRuntime(),
    if (eventId != null) 'eventId': eventId,
    if (platform != null) 'platform': platform,
    if (viewerName != null) 'viewerName': viewerName,
    if (amount != null) 'amount': amount,
    if (currency != null) 'currency': currency,
    if (title != null) 'title': title,
    if (message != null) 'message': message,
  };
}

final class OverlaySceneConfig {
  const OverlaySceneConfig({
    this.targetWidget,
    this.sceneKey,
    this.title,
    this.subtitle,
    this.accentColor,
  });

  factory OverlaySceneConfig.fromRuntime(RuntimeMap value) =>
      OverlaySceneConfig(
        targetWidget: overlayTargetFromRuntime(value['targetWidget']),
        sceneKey: _string(value['sceneKey']),
        title: _string(value['title']),
        subtitle: _string(value['subtitle']),
        accentColor: _string(value['accentColor']),
      );

  final OverlayTarget? targetWidget;
  final String? sceneKey;
  final String? title;
  final String? subtitle;
  final String? accentColor;

  RuntimeMap toRuntime() => {
    if (targetWidget != null) 'targetWidget': targetWidget!.toRuntime(),
    if (sceneKey != null) 'sceneKey': sceneKey,
    if (title != null) 'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (accentColor != null) 'accentColor': accentColor,
  };
}

final class OverlayEmoteConfig {
  const OverlayEmoteConfig({this.bouncer, this.message});

  factory OverlayEmoteConfig.fromRuntime(RuntimeMap value) =>
      OverlayEmoteConfig(
        bouncer: overlayTargetFromRuntime(value['bouncer']),
        message: _string(value['message']),
      );

  final OverlayTarget? bouncer;
  final String? message;

  RuntimeMap toRuntime() => {
    if (bouncer != null) 'bouncer': bouncer!.toRuntime(),
    if (message != null) 'message': message,
  };
}

enum OverlayVisibilityMode { enabled, disabled, toggle }

OverlayVisibilityMode overlayVisibilityModeFromRuntime(Object? value) =>
    switch (value?.toString().toLowerCase()) {
      'toggle' => OverlayVisibilityMode.toggle,
      'true' => OverlayVisibilityMode.enabled,
      _ =>
        value == true
            ? OverlayVisibilityMode.enabled
            : OverlayVisibilityMode.disabled,
    };

final class OverlayVisibilityConfig {
  const OverlayVisibilityConfig({this.widget, required this.mode});

  factory OverlayVisibilityConfig.fromRuntime(RuntimeMap value) =>
      OverlayVisibilityConfig(
        widget: overlayTargetFromRuntime(value['widget']),
        mode: overlayVisibilityModeFromRuntime(value['enabled']),
      );

  final OverlayTarget? widget;
  final OverlayVisibilityMode mode;

  RuntimeMap toRuntime() => {
    if (widget != null) 'widget': widget!.toRuntime(),
    'enabled': switch (mode) {
      OverlayVisibilityMode.enabled => true,
      OverlayVisibilityMode.disabled => false,
      OverlayVisibilityMode.toggle => 'toggle',
    },
  };
}

final class OverlayConfigCodec<C> implements PluginConfigCodec<C> {
  const OverlayConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final overlayTriggerWidgetConfigCodec = OverlayConfigCodec(
  OverlayTriggerWidgetConfig.fromRuntime,
  (OverlayTriggerWidgetConfig value) => value.toRuntime(),
);
final overlayAlertConfigCodec = OverlayConfigCodec(
  OverlayAlertConfig.fromRuntime,
  (OverlayAlertConfig value) => value.toRuntime(),
);
final overlayChatMessageConfigCodec = OverlayConfigCodec(
  OverlayChatMessageConfig.fromRuntime,
  (OverlayChatMessageConfig value) => value.toRuntime(),
);
final overlayPaidAlertConfigCodec = OverlayConfigCodec(
  OverlayPaidAlertConfig.fromRuntime,
  (OverlayPaidAlertConfig value) => value.toRuntime(),
);
final overlaySceneConfigCodec = OverlayConfigCodec(
  OverlaySceneConfig.fromRuntime,
  (OverlaySceneConfig value) => value.toRuntime(),
);
final overlayEmoteConfigCodec = OverlayConfigCodec(
  OverlayEmoteConfig.fromRuntime,
  (OverlayEmoteConfig value) => value.toRuntime(),
);
final overlayVisibilityConfigCodec = OverlayConfigCodec(
  OverlayVisibilityConfig.fromRuntime,
  (OverlayVisibilityConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

RuntimeMap? _mapOrNull(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
