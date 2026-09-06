part of '../satellite.dart';

final class RemoteResourceSlot {
  const RemoteResourceSlot({
    required this.id,
    required this.name,
    required this.resourceType,
    this.resourceId,
  });

  final String id;
  final String name;
  final String resourceType;
  final String? resourceId;

  RemoteResourceSlot copyWith({String? resourceId}) => RemoteResourceSlot(
    id: id,
    name: name,
    resourceType: resourceType,
    resourceId: resourceId,
  );
}
