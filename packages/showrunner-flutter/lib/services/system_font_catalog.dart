import 'package:flutter/services.dart';

/// Installed font families, shared by the overlay font selectors.
class SystemFontCatalog {
  SystemFontCatalog({this.channel = const MethodChannel('showrunner/input')});

  static final instance = SystemFontCatalog();
  final MethodChannel channel;
  Future<List<String>>? _fonts;
  List<String>? cachedFonts;

  Future<List<String>> load() => _fonts ??= _load();

  Future<List<String>> _load() async {
    List<String>? installed;
    try {
      installed = await channel.invokeListMethod<String>('listFontFamilies');
    } on MissingPluginException {
      // Native enumeration is available on Windows.
    } on PlatformException {
      // Keep the selector usable if the OS cannot enumerate its fonts.
    }
    final fonts =
        <String>{
              'Inter var',
              ...installed ??
                  const [
                    'Arial',
                    'Calibri',
                    'Cambria',
                    'Consolas',
                    'Courier New',
                    'Georgia',
                    'Impact',
                    'Segoe UI',
                    'Tahoma',
                    'Times New Roman',
                    'Trebuchet MS',
                    'Verdana',
                  ],
            }
            .where((font) => font.trim().isNotEmpty && !font.startsWith('@'))
            .map((font) => font.trim())
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return cachedFonts = List.unmodifiable(fonts);
  }
}
