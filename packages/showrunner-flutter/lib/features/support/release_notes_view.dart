import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef ReleaseNotesLinkHandler = Future<void> Function(Uri uri);

/// Renders the Markdown commonly used in GitHub release notes without
/// evaluating HTML or loading remote images into the desktop application.
class ReleaseNotesView extends StatefulWidget {
  const ReleaseNotesView({super.key, required this.source, this.onOpenLink});

  final String source;
  final ReleaseNotesLinkHandler? onOpenLink;

  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  late List<_ReleaseBlock> _blocks;
  final List<TapGestureRecognizer> _linkRecognizers = [];

  @override
  void initState() {
    super.initState();
    _parseSource();
  }

  @override
  void didUpdateWidget(covariant ReleaseNotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.onOpenLink != widget.onOpenLink) {
      _parseSource();
    }
  }

  @override
  void dispose() {
    _disposeLinkRecognizers();
    super.dispose();
  }

  void _disposeLinkRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }

  void _parseSource() {
    _disposeLinkRecognizers();
    _blocks = _parseBlocks(widget.source);
    for (final block in _blocks) {
      for (final part in block.parts) {
        final uri = part.link;
        final handler = widget.onOpenLink;
        if (uri == null || handler == null) continue;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => unawaited(handler(uri));
        part.recognizer = recognizer;
        _linkRecognizers.add(recognizer);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _blocks.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == _blocks.length - 1 ? 0 : 8,
            ),
            child: _buildBlock(context, _blocks[index], bodyStyle),
          ),
      ],
    );
  }

  Widget _buildBlock(
    BuildContext context,
    _ReleaseBlock block,
    TextStyle bodyStyle,
  ) {
    final theme = Theme.of(context);
    switch (block.kind) {
      case _ReleaseBlockKind.rule:
        return const Divider(height: 12);
      case _ReleaseBlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            block.text,
            style: bodyStyle.copyWith(fontFamily: 'Consolas', height: 1.35),
          ),
        );
      case _ReleaseBlockKind.heading:
        final fontSize = switch (block.level) {
          1 => 24.0,
          2 => 21.0,
          3 => 18.0,
          _ => 16.0,
        };
        return _inlineText(
          block.parts,
          bodyStyle.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        );
      case _ReleaseBlockKind.bullet:
      case _ReleaseBlockKind.numbered:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                block.marker,
                style: bodyStyle,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _inlineText(block.parts, bodyStyle)),
          ],
        );
      case _ReleaseBlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: _inlineText(
            block.parts,
            bodyStyle.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      case _ReleaseBlockKind.paragraph:
        return _inlineText(block.parts, bodyStyle);
    }
  }

  Widget _inlineText(List<_ReleaseInlinePart> parts, TextStyle baseStyle) {
    final span = TextSpan(
      style: baseStyle,
      children: _inlineSpans(parts, baseStyle),
    );
    if (parts.any((part) => part.recognizer != null)) return Text.rich(span);
    return SelectableText.rich(span);
  }

  List<InlineSpan> _inlineSpans(
    List<_ReleaseInlinePart> parts,
    TextStyle baseStyle,
  ) => [
    for (final part in parts)
      TextSpan(
        text: part.text,
        style: switch (part.kind) {
          _ReleaseInlineKind.strong => const TextStyle(
            fontWeight: FontWeight.bold,
          ),
          _ReleaseInlineKind.emphasis => const TextStyle(
            fontStyle: FontStyle.italic,
          ),
          _ReleaseInlineKind.strike => const TextStyle(
            decoration: TextDecoration.lineThrough,
          ),
          _ReleaseInlineKind.code => TextStyle(
            fontFamily: 'Consolas',
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          _ReleaseInlineKind.link => TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          _ReleaseInlineKind.text => baseStyle,
        },
        recognizer: part.recognizer,
      ),
  ];

  List<_ReleaseBlock> _parseBlocks(String source) {
    final blocks = <_ReleaseBlock>[];
    final paragraph = <String>[];
    final code = <String>[];
    var inCode = false;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(
        _ReleaseBlock(
          kind: _ReleaseBlockKind.paragraph,
          parts: _parseInline(paragraph.join('\n')),
        ),
      );
      paragraph.clear();
    }

    for (final line in source.replaceAll('\r', '').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        flushParagraph();
        if (inCode) {
          blocks.add(
            _ReleaseBlock(kind: _ReleaseBlockKind.code, text: code.join('\n')),
          );
          code.clear();
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        blocks.add(
          _ReleaseBlock(
            kind: _ReleaseBlockKind.heading,
            level: heading.group(1)!.length,
            parts: _parseInline(heading.group(2)!),
          ),
        );
        continue;
      }
      if (RegExp(r'^(---+|___+|\*\*\*+)$').hasMatch(trimmed)) {
        flushParagraph();
        blocks.add(const _ReleaseBlock(kind: _ReleaseBlockKind.rule));
        continue;
      }

      final bullet = RegExp(r'^\s*[-+*]\s+(.+)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        blocks.add(
          _ReleaseBlock(
            kind: _ReleaseBlockKind.bullet,
            marker: '•',
            parts: _parseInline(bullet.group(1)!),
          ),
        );
        continue;
      }
      final numbered = RegExp(r'^\s*(\d+[.)])\s+(.+)$').firstMatch(line);
      if (numbered != null) {
        flushParagraph();
        blocks.add(
          _ReleaseBlock(
            kind: _ReleaseBlockKind.numbered,
            marker: numbered.group(1)!,
            parts: _parseInline(numbered.group(2)!),
          ),
        );
        continue;
      }
      final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
      if (quote != null) {
        flushParagraph();
        blocks.add(
          _ReleaseBlock(
            kind: _ReleaseBlockKind.quote,
            parts: _parseInline(quote.group(1)!),
          ),
        );
        continue;
      }
      paragraph.add(line);
    }
    flushParagraph();
    if (code.isNotEmpty) {
      blocks.add(
        _ReleaseBlock(kind: _ReleaseBlockKind.code, text: code.join('\n')),
      );
    }
    return blocks;
  }

  List<_ReleaseInlinePart> _parseInline(String text) {
    final parts = <_ReleaseInlinePart>[];
    final markup = RegExp(
      r'(!?\[[^\]]+\]\([^)]*\)|`[^`]+`|\*\*.+?\*\*|__.+?__|~~.+?~~|\*[^*]+\*|_[^_]+_)',
    );
    var previousEnd = 0;
    for (final match in markup.allMatches(text)) {
      if (match.start > previousEnd) {
        parts.add(_ReleaseInlinePart(text.substring(previousEnd, match.start)));
      }
      final token = match.group(0)!;
      final link = RegExp(r'^(!?)\[([^\]]+)\]\(([^)]*)\)$').firstMatch(token);
      if (link != null) {
        final rawUrl = link.group(3)!.trim().split(RegExp(r'\s+')).first;
        final uri = Uri.tryParse(rawUrl);
        final safeUri =
            uri != null &&
                (uri.scheme == 'https' || uri.scheme == 'http') &&
                uri.host.isNotEmpty
            ? uri
            : null;
        parts.add(
          _ReleaseInlinePart(
            link.group(2)!,
            kind: safeUri == null
                ? _ReleaseInlineKind.text
                : _ReleaseInlineKind.link,
            link: safeUri,
          ),
        );
      } else if (token.startsWith('`')) {
        parts.add(
          _ReleaseInlinePart(
            token.substring(1, token.length - 1),
            kind: _ReleaseInlineKind.code,
          ),
        );
      } else if (token.startsWith('**') || token.startsWith('__')) {
        parts.add(
          _ReleaseInlinePart(
            token.substring(2, token.length - 2),
            kind: _ReleaseInlineKind.strong,
          ),
        );
      } else if (token.startsWith('~~')) {
        parts.add(
          _ReleaseInlinePart(
            token.substring(2, token.length - 2),
            kind: _ReleaseInlineKind.strike,
          ),
        );
      } else {
        parts.add(
          _ReleaseInlinePart(
            token.substring(1, token.length - 1),
            kind: _ReleaseInlineKind.emphasis,
          ),
        );
      }
      previousEnd = match.end;
    }
    if (previousEnd < text.length) {
      parts.add(_ReleaseInlinePart(text.substring(previousEnd)));
    }
    return parts;
  }
}

enum _ReleaseBlockKind {
  paragraph,
  heading,
  bullet,
  numbered,
  quote,
  code,
  rule,
}

class _ReleaseBlock {
  const _ReleaseBlock({
    required this.kind,
    this.text = '',
    this.level = 0,
    this.marker = '',
    this.parts = const [],
  });

  final _ReleaseBlockKind kind;
  final String text;
  final int level;
  final String marker;
  final List<_ReleaseInlinePart> parts;
}

enum _ReleaseInlineKind { text, strong, emphasis, strike, code, link }

class _ReleaseInlinePart {
  _ReleaseInlinePart(
    this.text, {
    this.kind = _ReleaseInlineKind.text,
    this.link,
  });

  final String text;
  final _ReleaseInlineKind kind;
  final Uri? link;
  TapGestureRecognizer? recognizer;
}
