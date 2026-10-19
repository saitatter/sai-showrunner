import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';

/// Presentation metadata mirrored from the reference integration catalog.
///
/// Plugin contracts stay independent from Flutter; this mapping is kept at
/// the UI boundary so manifests remain usable by runtime and schema code
/// without importing Material icons or colors.
IconData pluginIconFor(String id) => switch (id) {
  'ShowRunner' => mdiIcon(0xF046E),
  'advss' => mdiIcon(0xF0C8C),
  'aitum' => mdiIcon(0xF0FE8),
  'bluesky' => mdiIcon(0xF0163),
  'dashboards' => mdiIcon(0xF0A1D),
  'discord' => Icons.forum_outlined,
  'donordrive' => mdiIcon(0xF157E),
  'elgato' => mdiIcon(0xF097B),
  'govee' => mdiIcon(0xF1051),
  'heartrate' => Icons.favorite_outline,
  'http' => mdiIcon(0xF059F),
  'input' => mdiIcon(0xF030C),
  'iot' => mdiIcon(0xF061A),
  'lifx' => mdiIcon(0xF06E9),
  'minecraft' => mdiIcon(0xF0373),
  'moderation' => mdiIcon(0xF0565),
  'obs' => Icons.tv,
  'os' => mdiIcon(0xF0379),
  'overlays' => mdiIcon(0xF09FE),
  'philips-hue' => mdiIcon(0xF1254),
  'random' => mdiIcon(0xF1156),
  'remote' => mdiIcon(0xF0454),
  'sound' => mdiIcon(0xF057E),
  'spellcast' => mdiIcon(0xF0068),
  'stream-plans' => mdiIcon(0xF00F0),
  'time' => mdiIcon(0xF0150),
  'tplink-kasa' => mdiIcon(0xF0427),
  'twinkly' => mdiIcon(0xF12BA),
  'twitch' => mdiIcon(0xF0543),
  'variables' => mdiIcon(0xF0AE7),
  'voicemod' => mdiIcon(0xF0370),
  'wyze' => mdiIcon(0xF07AE),
  'youtube' => mdiIcon(0xF05C3),
  _ => mdiIcon(0xF0A66),
};

Widget pluginIconWidgetFor(
  String id, {
  required Color color,
  double size = 16,
}) => switch (id) {
  'obs' => ObsBrandIcon(color: color, size: size),
  'discord' => BrandSvgIcon(
    asset: 'assets/icons/discord.svg',
    color: color,
    size: size,
  ),
  'advss' => BrandSvgIcon(
    asset: 'assets/icons/advss.svg',
    color: color,
    size: size,
  ),
  'aitum' => BrandSvgIcon(
    asset: 'assets/icons/aitum.svg',
    color: color,
    size: size,
  ),
  _ => Icon(pluginIconFor(id), size: size, color: color),
};

Color pluginColorFor(String id) => switch (id) {
  'obs' => const Color(0xff256eff),
  'youtube' => const Color(0xffff5f56),
  'twitch' => const Color(0xff9146ff),
  'heartrate' => const Color(0xfff43f5e),
  'discord' => const Color(0xff5865f2),
  'bluesky' => const Color(0xff208bfe),
  'moderation' => const Color(0xff22c55e),
  'sound' => const Color(0xfff59e0b),
  _ => const Color(0xff2dd4bf),
};

/// Descriptions mirrored from the reference integration manifests.
///
/// This is presentation metadata rather than part of the runtime contract;
/// keeping it here means plugin manifests remain usable without Flutter.
String pluginDescriptionFor(String id) => switch (id) {
  'advss' => 'Integration for Advanced Scene Switcher by WarmUpTill',
  'aitum' => 'Integration for Aitum OBS Plugins',
  'bluesky' => 'Blue Sky',
  'dashboards' => 'DASHBOARDS',
  'discord' => 'UI Description',
  'donordrive' => '',
  'elgato' => 'UI Description',
  'heartrate' => 'Bluetooth heart-rate monitoring and streaming overlays.',
  'http' => 'UI Description',
  'input' => 'Input!',
  'iot' => 'UI Description',
  'minecraft' => 'Communicate with minecraft servers via RCON',
  'moderation' => 'Connects ShowRunner events to the SAI moderation docker.',
  'obs' => 'Provides OBS Control over OBS Websocket 5',
  'os' => 'Operating System',
  'overlays' => 'Overlay Plugin',
  'random' => 'Randomness',
  'remote' => 'Allows various programs to remotely trigger ShowRunner',
  'sound' => 'SOUND!',
  'spellcast' => 'UI Description',
  'stream-plans' => 'Stream Plan',
  'time' => 'Time Utilities',
  'twitch' => 'Provides Twitch triggers for chat, raids, and more',
  'voicemod' => 'Control VoiceMod with ShowRunner',
  'youtube' =>
    'Provides YouTube Live triggers for chat, memberships, and paid messages.',
  _ => '',
};
