import 'package:flutter/material.dart';

class DashboardScroll extends StatelessWidget {
  const DashboardScroll({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(12), children: children);
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.iconWidget,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              iconWidget ?? Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class DashboardStatItem extends StatelessWidget {
  const DashboardStatItem({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleMedium),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
