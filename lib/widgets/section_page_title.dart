import 'package:flutter/material.dart';

class SectionPageTitle extends StatelessWidget {
  const SectionPageTitle({
    super.key,
    required this.pageTitle,
  });

  final String pageTitle;

  @override
  Widget build(BuildContext context) {
    return Text(pageTitle);
  }
}

