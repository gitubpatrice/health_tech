import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/generated/app_localizations.dart';
import '../legal/legal_screen.dart';

/// Page « À propos » : version (lue dynamiquement via PackageInfo, jamais
/// hardcodée — leçon partagée avec PDF/Pass/Notes Tech), identité éditeur,
/// contact, modèle de confidentialité, licence, et lien vers les documents
/// légaux.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutScreenTitle)),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.hasData
              ? '${snap.data!.version} (${snap.data!.buildNumber})'
              : '…';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.spa_outlined,
                      size: 32,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.appTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.aboutTagline,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _AboutRow(
                icon: Icons.tag,
                label: l10n.aboutVersionLabel,
                value: version,
              ),
              _AboutRow(
                icon: Icons.business_outlined,
                label: l10n.aboutEditorLabel,
                value: l10n.aboutEditorValue,
              ),
              _AboutRow(
                icon: Icons.alternate_email,
                label: l10n.aboutContactLabel,
                value: l10n.aboutContactValue,
                trailing: IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: l10n.aboutCopyContact,
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: l10n.aboutContactValue),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.aboutCopyContact)),
                    );
                  },
                ),
              ),
              _AboutRow(
                icon: Icons.lock_outline,
                label: l10n.aboutPrivacyLabel,
                value: l10n.aboutPrivacyValue,
              ),
              _AboutRow(
                icon: Icons.description_outlined,
                label: l10n.aboutLicenseLabel,
                value: l10n.aboutLicenseValue,
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const LegalScreen()),
                ),
                icon: const Icon(Icons.gavel_outlined),
                label: Text(l10n.aboutLegalLink),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
