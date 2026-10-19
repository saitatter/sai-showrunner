final class OverlayPresence {
  const OverlayPresence({
    required this.overlayId,
    required this.connected,
    required this.subscribers,
  });

  final String overlayId;
  final bool connected;
  final int subscribers;

  factory OverlayPresence.disconnected(String overlayId) =>
      OverlayPresence(overlayId: overlayId, connected: false, subscribers: 0);

  @override
  bool operator ==(Object other) =>
      other is OverlayPresence &&
      other.overlayId == overlayId &&
      other.connected == connected &&
      other.subscribers == subscribers;

  @override
  int get hashCode => Object.hash(overlayId, connected, subscribers);
}

abstract interface class OverlayPresenceReader {
  Future<OverlayPresence> getPresence(String overlayId);

  String browserSourceUrl(String overlayId);
}
