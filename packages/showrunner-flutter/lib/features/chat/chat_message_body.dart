import 'package:flutter/material.dart';
import 'chat_emote.dart';

class ChatMessageBody extends StatelessWidget {
  const ChatMessageBody({
    super.key,
    required this.parts,
    required this.animate,
    required this.style,
  });
  final List<ChatTextPart> parts;
  final bool animate;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => SelectionArea(
    child: Text.rich(
      TextSpan(
        children: [
          for (final part in parts)
            if (part.emote?.image(animate: animate) case final url?)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Tooltip(
                  message: part.text,
                  child: Image.network(
                    url,
                    height: (style.fontSize ?? 14) * 1.7,
                    width: (style.fontSize ?? 14) * 2,
                    fit: BoxFit.contain,
                    semanticLabel: part.text,
                    errorBuilder: (_, _, _) => Text(part.text, style: style),
                  ),
                ),
              )
            else
              TextSpan(text: part.text),
        ],
      ),
      style: style,
    ),
  );
}
