import 'package:flutter/material.dart';

/// Form / detail section header. Replaces three private `_SectionTitle`
/// duplicates that lived in client/animal/session form screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
