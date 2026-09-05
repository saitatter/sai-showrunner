import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../design_system/tokens/tokens.dart';
import 'commands/app_command.dart';

/// The application chrome equivalent of the reference PrimeVue menubar.
///
/// Keeping this outside the shell makes the title bar independent from the
/// workspace contents and gives menus, shortcuts and window controls one
/// stable place to evolve.
class ShowRunnerSystemBar extends StatelessWidget {
  const ShowRunnerSystemBar({super.key, required this.commands});

  final AppCommandRegistry commands;

  @override
  Widget build(BuildContext context) {
    final commandContext = AppCommandContext(buildContext: context);

    void runCommand(String id) {
      unawaited(commands.run(id, commandContext));
    }

    return Material(
      color: ShowRunnerColors.surfaceA,
      child: Container(
        height: ShowRunnerSpacing.toolbarHeight,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ShowRunnerColors.surfaceBorder),
          ),
        ),
        child: DragToMoveArea(
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 12, right: 10),
                child: ShowRunnerBrandMark(),
              ),
              _SystemMenuButton(
                label: 'File',
                onSelected: runCommand,
                itemBuilder: (context) => [
                  _commandMenuItem('file.newProfile', commandContext, commands),
                  _commandMenuItem(
                    'file.newAutomation',
                    commandContext,
                    commands,
                  ),
                  _commandMenuItem(
                    'file.newAutomationFromStarter',
                    commandContext,
                    commands,
                  ),
                  const PopupMenuDivider(),
                  _commandMenuItem('file.save', commandContext, commands),
                  _commandMenuItem('file.saveAll', commandContext, commands),
                  const PopupMenuDivider(),
                  _commandMenuItem('file.settings', commandContext, commands),
                  _commandMenuItem('file.close', commandContext, commands),
                  _commandMenuItem(
                    'file.closeOthers',
                    commandContext,
                    commands,
                  ),
                  const PopupMenuDivider(),
                  _commandMenuItem('file.exit', commandContext, commands),
                ],
              ),
              _SystemMenuButton(
                label: 'Help',
                onSelected: runCommand,
                itemBuilder: (context) => [
                  _commandMenuItem('help.about', commandContext, commands),
                  _commandMenuItem('help.updates', commandContext, commands),
                  _commandMenuItem('help.discord', commandContext, commands),
                  _commandMenuItem(
                    'help.openLogFolder',
                    commandContext,
                    commands,
                  ),
                ],
              ),
              const Spacer(),
              if (Platform.isWindows) const ShowRunnerWindowControls(),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemMenuButton extends StatelessWidget {
  const _SystemMenuButton({
    required this.label,
    required this.onSelected,
    required this.itemBuilder,
  });

  final String label;
  final ValueChanged<String> onSelected;
  final PopupMenuItemBuilder<String> itemBuilder;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    onSelected: onSelected,
    itemBuilder: itemBuilder,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Text(label),
  );
}

PopupMenuItem<String> _commandMenuItem(
  String id,
  AppCommandContext context,
  AppCommandRegistry commands,
) {
  final command = commands.find(id);
  if (command == null) {
    throw StateError('Command is not registered: $id');
  }
  return PopupMenuItem<String>(
    value: id,
    enabled: command.canExecute(context),
    child: Row(
      children: [
        if (command.icon != null) ...[
          Icon(command.icon, size: 18),
          const SizedBox(width: 10),
        ],
        Text(command.label),
      ],
    ),
  );
}

class ShowRunnerBrandMark extends StatelessWidget {
  const ShowRunnerBrandMark({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 28,
    height: 28,
    child: CustomPaint(painter: _ShowRunnerBrandPainter()),
  );
}

class _ShowRunnerBrandPainter extends CustomPainter {
  const _ShowRunnerBrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 40;
    canvas.scale(scale);
    final outer = Paint()
      ..color = const Color(0xff14131a)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = const Color(0xff8a5cff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 38, 38),
        const Radius.circular(10),
      ),
      outer,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 38, 38),
        const Radius.circular(10),
      ),
      outline,
    );

    final body = Paint()
      ..color = const Color(0xff1b1b27)
      ..style = PaintingStyle.fill;
    final bodyOutline = Paint()
      ..color = const Color(0xfff2f0ff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 13, 22, 16),
        const Radius.circular(6),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 13, 22, 16),
        const Radius.circular(6),
      ),
      bodyOutline,
    );
    canvas.drawCircle(
      const Offset(20, 21),
      5.5,
      Paint()
        ..color = const Color(0xff14131a)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      const Offset(20, 21),
      5.5,
      Paint()
        ..color = const Color(0xff8a5cff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      const Offset(20, 21),
      1.8,
      Paint()..color = const Color(0xff20d6b5),
    );
    final antenna = Path()
      ..moveTo(14, 14)
      ..lineTo(16, 10.5)
      ..lineTo(24, 10.5)
      ..lineTo(26, 14)
      ..close();
    canvas.drawPath(antenna, Paint()..color = const Color(0xfff2f0ff));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ShowRunnerWindowControls extends StatefulWidget {
  const ShowRunnerWindowControls({super.key});

  @override
  State<ShowRunnerWindowControls> createState() =>
      _ShowRunnerWindowControlsState();
}

class _ShowRunnerWindowControlsState extends State<ShowRunnerWindowControls>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_readMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _readMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (_maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _readMaximized();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _WindowButton(
        tooltip: 'Minimize',
        icon: Icons.minimize,
        onPressed: windowManager.minimize,
      ),
      _WindowButton(
        tooltip: _maximized ? 'Restore' : 'Maximize',
        icon: _maximized ? Icons.filter_none : Icons.crop_square,
        onPressed: _toggleMaximize,
      ),
      _WindowButton(
        tooltip: 'Close',
        icon: Icons.close,
        onPressed: windowManager.close,
      ),
    ],
  );
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 17),
    visualDensity: VisualDensity.compact,
    splashRadius: 18,
  );
}
