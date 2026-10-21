import 'package:showrunner_flutter/components/data_inputs/numeric_input_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/features/resources/color_field.dart';

import 'package:showrunner_flutter/components/data_inputs/resource_form.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_field_values.dart';

class ChannelPointRewardEditor extends StatefulWidget {
  const ChannelPointRewardEditor({
    super.key,
    required this.resource,
    required this.onSave,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<ChannelPointRewardEditor> createState() =>
      _ChannelPointRewardEditorState();
}

class _ChannelPointRewardEditorState extends State<ChannelPointRewardEditor> {
  late final TextEditingController _name;
  late final TextEditingController _twitchId;
  late final TextEditingController _prompt;
  late final TextEditingController _cost;
  late final TextEditingController _cooldown;
  late final TextEditingController _maxPerStream;
  late final TextEditingController _maxPerUser;
  late bool _controllable;
  late bool _transient;
  late bool _allowEnable;
  late bool _userInputRequired;
  late bool _skipQueue;
  late String _backgroundColor;

  Map<String, dynamic> get _configuredRewardData {
    final configured = widget.resource.config['rewardData'];
    return configured is Map
        ? Map<String, dynamic>.from(configured)
        : <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    final config = widget.resource.config;
    final rewardData = _configuredRewardData;
    _name = TextEditingController(
      text: ResourceFieldValues.display(config['name'] ?? config['title']),
    );
    _twitchId = TextEditingController(
      text: ResourceFieldValues.display(config['twitchId']),
    );
    _prompt = TextEditingController(
      text: ResourceFieldValues.display(rewardData['prompt']),
    );
    _cost = TextEditingController(
      text: ResourceFieldValues.display(rewardData['cost'] ?? 100),
    );
    _cooldown = TextEditingController(
      text: ResourceFieldValues.display(rewardData['cooldown']),
    );
    _maxPerStream = TextEditingController(
      text: ResourceFieldValues.display(rewardData['maxRedemptionsPerStream']),
    );
    _maxPerUser = TextEditingController(
      text: ResourceFieldValues.display(
        rewardData['maxRedemptionsPerUserPerStream'],
      ),
    );
    _controllable = config['controllable'] != false;
    _transient = config['transient'] == true;
    _allowEnable = config['allowEnable'] != false;
    _userInputRequired = rewardData['userInputRequired'] == true;
    _skipQueue = rewardData['skipQueue'] == true;
    _backgroundColor = ResourceFieldValues.display(
      rewardData['backgroundColor'] ?? '#9147ff',
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _twitchId,
      _prompt,
      _cost,
      _cooldown,
      _maxPerStream,
      _maxPerUser,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceForm(
    title: 'Edit Twitch channel point reward',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: _twitchId,
        decoration: const InputDecoration(
          labelText: 'Twitch reward ID',
          hintText: 'Leave empty until Twitch creates it',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Controllable by ShowRunner'),
        subtitle: const Text(
          'When disabled, the reward is observed from Twitch but not managed by profiles.',
        ),
        value: _controllable,
        onChanged: (value) => setState(() => _controllable = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow enable/disable'),
        value: _allowEnable,
        onChanged: (value) => setState(() => _allowEnable = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Transient reward'),
        subtitle: const Text('Do not recreate it on Twitch when missing.'),
        value: _transient,
        onChanged: (value) => setState(() => _transient = value),
      ),
      TextField(
        controller: _prompt,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Prompt'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cost,
              inputFormatters: const [
                NumericInputFormatter(decimal: false, signed: false),
              ],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cost'),
            ),
          ),
          const SizedBox(width: 12),
          ColorValueField(
            label: 'Color',
            initialValue: _backgroundColor,
            onChanged: (value) => setState(() => _backgroundColor = value),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Require viewer input'),
        value: _userInputRequired,
        onChanged: (value) => setState(() => _userInputRequired = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Skip redemption queue'),
        value: _skipQueue,
        onChanged: (value) => setState(() => _skipQueue = value),
      ),
      TextField(
        controller: _cooldown,
        inputFormatters: const [
          NumericInputFormatter(decimal: false, signed: false),
        ],
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Global cooldown (seconds)',
          hintText: 'Optional',
        ),
      ),
      TextField(
        controller: _maxPerStream,
        inputFormatters: const [
          NumericInputFormatter(decimal: false, signed: false),
        ],
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Max redemptions per stream',
          hintText: 'Optional',
        ),
      ),
      TextField(
        controller: _maxPerUser,
        inputFormatters: const [
          NumericInputFormatter(decimal: false, signed: false),
        ],
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Max redemptions per viewer per stream',
          hintText: 'Optional',
        ),
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'twitchId': _twitchId.text.trim(),
          'controllable': _controllable,
          'transient': _transient,
          'allowEnable': _allowEnable,
          'rewardData': {
            ..._configuredRewardData,
            'prompt': _prompt.text,
            'backgroundColor': _backgroundColor.trim(),
            'userInputRequired': _userInputRequired,
            'cost': (int.tryParse(_cost.text.trim()) ?? 1).clamp(1, 1000000),
            'cooldown': _optionalPositiveInt(_cooldown.text),
            'maxRedemptionsPerStream': _optionalPositiveInt(_maxPerStream.text),
            'maxRedemptionsPerUserPerStream': _optionalPositiveInt(
              _maxPerUser.text,
            ),
            'skipQueue': _skipQueue,
          },
        },
        state: widget.resource.state,
      ),
    ),
  );

  int? _optionalPositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    return parsed == null || parsed < 1 ? null : parsed;
  }
}
