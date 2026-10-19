import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';
import 'overlay_widget_catalog.dart';

/// Widget icons mirrored from the reference overlay editor.
///
/// Resolve the MDI class from the shared widget catalog so the add menu, widget
/// list, and other Flutter surfaces use the same icon declaration.
IconData overlayWidgetIconFor(GeneratedOverlayWidget widget) {
  final manifestIcon = _mdiIconForClass(widget.icon);
  if (manifestIcon != null) return manifestIcon;

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

IconData? _mdiIconForClass(String? value) {
  if (value == null) return null;
  final iconClass = value
      .split(RegExp(r'\s+'))
      .where((name) => name.startsWith('mdi-'))
      .firstOrNull;
  final codePoint = switch (iconClass) {
    'mdi-alert-box-outline' => 0xF0CE4,
    'mdi-square' => 0xF0764,
    'mdi-chat-processing-outline' => 0xF12CA,
    'mdi-emoticon' => 0xF0C68,
    'mdi-cursor-text' => 0xF05E7,
    'mdi-table' => 0xF04EB,
    'mdi-motion-play-outline' => 0xF1591,
    'mdi-magic-staff' => 0xF1844,
    'mdi-tire' => 0xF1896,
    'mdi-heart-pulse' => 0xF05F6,
    'mdi-chart-line' => 0xF012A,
    _ => null,
  };
  return codePoint == null ? null : mdiIcon(codePoint);
}

Widget overlayWidgetIconWidget(
  GeneratedOverlayWidget widget, {
  Color? color,
  double size = 18,
}) => Icon(overlayWidgetIconFor(widget), color: color, size: size);
