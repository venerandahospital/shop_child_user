import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

class AdaptiveCardText extends StatelessWidget {
  const AdaptiveCardText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.minFontSize = 10,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final double minFontSize;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AutoSizeText(
      text,
      style: style,
      maxLines: maxLines,
      minFontSize: minFontSize,
      overflow: overflow,
      textAlign: textAlign,
      stepGranularity: 0.5,
    );
  }
}
