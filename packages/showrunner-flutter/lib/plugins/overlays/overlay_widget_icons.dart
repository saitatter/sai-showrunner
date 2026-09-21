import 'package:flutter/material.dart';

import 'overlay_widget_catalog.dart';

/// Widget icons mirrored from the reference overlay editor.
///
/// The catalog keeps the original MDI class for browser consumers. Flutter
/// resolves the same visual meaning locally because CSS icon classes cannot be
/// rendered by the desktop UI.
IconData overlayWidgetIconFor(GeneratedOverlayWidget widget) {
  if (widget.pluginId == 'heartrate') {
    return switch (widget.id) {
      'heartRateGraph' => Icons.show_chart,
      'heartRateZone' => Icons.monitor_heart_outlined,
      _ => Icons.favorite_outline,
    };
  }

  return switch ('${widget.pluginId}.${widget.id}') {
    'overlays.alert' => Icons.notifications_active_outlined,
    'overlays.bar' => Icons.horizontal_rule,
    'overlays.chatFeed' => Icons.chat_bubble_outline,
    'overlays.emote-bounce' => Icons.emoji_emotions_outlined,
    'overlays.label' => Icons.text_fields,
    'overlays.leaderboard' => Icons.leaderboard_outlined,
    'overlays.paidAlert' => Icons.payments_outlined,
    'overlays.sceneBanner' => Icons.campaign_outlined,
    'overlays.shaderLayer' => Icons.auto_awesome,
    'random.wheel' => Icons.casino_outlined,
    _ => Icons.widgets_outlined,
  };
}

Widget overlayWidgetIconWidget(
  GeneratedOverlayWidget widget, {
  Color? color,
  double size = 18,
}) => Icon(overlayWidgetIconFor(widget), color: color, size: size);
