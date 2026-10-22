import 'package:flutter/material.dart';
import '../../../services/system_font_catalog.dart';

class OverlayFontFamilyInput extends StatefulWidget {
  const OverlayFontFamilyInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<OverlayFontFamilyInput> createState() => _OverlayFontFamilyInputState();
}

class _OverlayFontFamilyInputState extends State<OverlayFontFamilyInput> {
  late final _fonts = SystemFontCatalog.instance.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _fonts,
    initialData: SystemFontCatalog.instance.cachedFonts,
    builder: (context, snapshot) {
      final fonts = <String>{
        if (widget.value.isNotEmpty) widget.value,
        ...?snapshot.data,
      }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return LayoutBuilder(
        builder: (context, constraints) => MenuAnchor(
          style: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Color(0xff202020)),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          ),
          menuChildren: [
            SizedBox(
              width: constraints.maxWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final font in fonts)
                        MenuItemButton(
                          onPressed: () => widget.onChanged(font),
                          child: Text(font, style: TextStyle(fontFamily: font)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          builder: (context, controller, _) => InkWell(
            key: const ValueKey('overlay-font-family-dropdown'),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: widget.label,
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: widget.value, fontSize: 16),
              ),
            ),
          ),
        ),
      );
    },
  );
}
