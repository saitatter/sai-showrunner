import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/resource.dart';

import 'dashboard_widgets.dart';

class ObsConnectionDashboardCard extends StatelessWidget {
  const ObsConnectionDashboardCard({
    super.key,
    required this.connection,
    required this.registryFuture,
    required this.onOpenControls,
    required this.onEdit,
  });

  final ResourceData connection;
  final Future<DartPluginRegistry> registryFuture;
  final VoidCallback onOpenControls;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    child: DashboardCard(
      iconWidget: const ObsBrandIcon(size: 18),
      title: connection.name,
      child: FutureBuilder<bool>(
        future: registryFuture.then(
          (registry) => registry.checkHealthId(const PluginId('obs')),
        ),
        builder: (context, snapshot) {
          final healthy = snapshot.data == true;
          final checking = snapshot.connectionState == ConnectionState.waiting;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    checking
                        ? Icons.sync
                        : healthy
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: checking
                        ? null
                        : healthy
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      checking
                          ? 'Checking connection...'
                          : healthy
                          ? 'Connected and responding.'
                          : 'Not connected or not configured.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onOpenControls,
                    child: const Text('Open OBS controls'),
                  ),
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}
