import 'package:flutter/widgets.dart';

import 'flutter_plugin_ui_contract.dart';

export 'flutter_plugin_ui_contract.dart';

typedef DartPluginWorkspaceBuilder =
    Widget Function(BuildContext context, DartPluginUiHostContext host);

final class DartFlutterPluginUiContribution
    implements DartPluginUiContribution {
  const DartFlutterPluginUiContribution({required this.builder});

  final DartPluginWorkspaceBuilder builder;

  @override
  Widget build(BuildContext context, DartPluginUiHostContext host) =>
      builder(context, host);
}
