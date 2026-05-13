import 'package:flutter/material.dart';

/// État vide unifié (audit UI M4). Remplace les `Center(Text(...))`
/// ad hoc disséminés dans les écrans liste. Donne un indice visuel
/// (icône cs.outline), un titre fort et, optionnellement, une action
/// d'amorçage pour guider l'utilisateur vers la première création.
///
/// Pattern propagé à clients, animals (tab), sessions (tab) et agenda.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
