import 'package:flutter/material.dart';

/// Presentation metadata mirrored from the reference integration catalog.
///
/// Plugin contracts stay independent from Flutter; this mapping is kept at
/// the UI boundary so manifests remain usable by runtime and schema code
/// without importing Material icons or colors.
IconData pluginIconFor(String id) => switch (id) {
  'ShowRunner' => Icons.directions_run,
  'advss' => Icons.apps,
  'aitum' => Icons.link,
  'bluesky' => Icons.cloud_outlined,
  'dashboards' => Icons.dashboard_outlined,
  'discord' => Icons.forum_outlined,
  'donordrive' => Icons.volunteer_activism_outlined,
  'elgato' => Icons.keyboard_outlined,
  'govee' => Icons.lightbulb_outline,
  'http' => Icons.language,
  'input' => Icons.keyboard_alt_outlined,
  'iot' => Icons.memory,
  'lifx' => Icons.lightbulb_outline,
  'minecraft' => Icons.view_in_ar_outlined,
  'moderation' => Icons.shield_outlined,
  'obs' => Icons.tv,
  'os' => Icons.desktop_windows_outlined,
  'overlays' => Icons.layers_outlined,
  'philips-hue' => Icons.lightbulb,
  'random' => Icons.casino_outlined,
  'remote' => Icons.settings_remote_outlined,
  'sound' => Icons.volume_up_outlined,
  'spellcast' => Icons.auto_fix_high_outlined,
  'stream-plans' => Icons.calendar_month_outlined,
  'time' => Icons.schedule_outlined,
  'tplink-kasa' => Icons.power_outlined,
  'twinkly' => Icons.wb_incandescent_outlined,
  'twitch' => Icons.live_tv,
  'variables' => Icons.data_object,
  'voicemod' => Icons.mic_none_outlined,
  'wyze' => Icons.videocam_outlined,
  'youtube' => Icons.smart_display,
  _ => Icons.extension_outlined,
};

Color pluginColorFor(String id) => switch (id) {
  'obs' => const Color(0xff8b9bb4),
  'youtube' => const Color(0xffff5f56),
  'twitch' => const Color(0xffa970ff),
  'discord' => const Color(0xff5865f2),
  'bluesky' => const Color(0xff208bfe),
  'moderation' => const Color(0xff22c55e),
  'sound' => const Color(0xfff59e0b),
  _ => const Color(0xff2dd4bf),
};
