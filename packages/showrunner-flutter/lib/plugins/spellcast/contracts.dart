import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class SpellcastSpellReference {
  const SpellcastSpellReference(this.id);

  factory SpellcastSpellReference.fromRuntime(Object? value) {
    if (value is Map) {
      return SpellcastSpellReference(
        (value['id'] ?? value['resourceId'] ?? '').toString().trim(),
      );
    }
    return SpellcastSpellReference(value?.toString().trim() ?? '');
  }

  final String id;

  bool get isValid => id.isNotEmpty;

  String toRuntime() => id;
}

final class SpellcastCastConfig {
  const SpellcastCastConfig({this.spell});

  factory SpellcastCastConfig.fromRuntime(RuntimeMap value) =>
      SpellcastCastConfig(
        spell: SpellcastSpellReference.fromRuntime(
          value['spell'] ?? value['spellId'],
        ),
      );

  final SpellcastSpellReference? spell;

  RuntimeMap toRuntime() => {
    if (spell?.isValid == true) 'spell': spell!.toRuntime(),
  };
}

final class SpellcastHookConfig {
  const SpellcastHookConfig({required this.spell});

  factory SpellcastHookConfig.fromRuntime(RuntimeMap value) =>
      SpellcastHookConfig(
        spell: SpellcastSpellReference.fromRuntime(value['spell']),
      );

  final SpellcastSpellReference spell;

  RuntimeMap toRuntime() => {'spell': spell.toRuntime()};
}

final class SpellcastHookEvent {
  const SpellcastHookEvent({required this.spell, this.payload = const {}});

  factory SpellcastHookEvent.fromRuntime(RuntimeMap value) =>
      SpellcastHookEvent(
        spell: SpellcastSpellReference.fromRuntime(
          value['spell'] ?? value['spellId'],
        ),
        payload: Map<String, dynamic>.from(value),
      );

  final SpellcastSpellReference spell;
  final RuntimeMap payload;

  RuntimeMap toRuntime() => Map<String, dynamic>.from(payload);
}

final class SpellcastConfigCodec<C> implements PluginConfigCodec<C> {
  const SpellcastConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final spellcastCastConfigCodec = SpellcastConfigCodec(
  SpellcastCastConfig.fromRuntime,
  (SpellcastCastConfig value) => value.toRuntime(),
);

final spellcastHookConfigCodec = SpellcastConfigCodec(
  SpellcastHookConfig.fromRuntime,
  (SpellcastHookConfig value) => value.toRuntime(),
);

String spellcastResourceId(Object? value) =>
    SpellcastSpellReference.fromRuntime(value).id;
