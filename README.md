# Health Tech

Application Android (téléphone + tablette) de gestion d'agenda, clients humains, animaux et séances pour praticien·ne·s du **bien-être** (énergéticien·ne·s, magnétiseur·euse·s, Reiki, ostéopathie animalière, géobiologie, sophrologie…).

**100 % local, aucun cloud, aucun tracker.** L'application n'a même pas la permission Internet dans son manifest Android — elle est techniquement incapable d'envoyer la moindre donnée.

## Statut

`v1.4.4` — production. Audité (zéro vulnérabilité, zéro faille). 75 / 75 tests verts. flutter analyze 0 issue.

Voir [`SECURITY.md`](SECURITY.md), [`PRIVACY.md`](PRIVACY.md) et la page éditeur https://www.files-tech.com/health-tech.php.

## Pile technique

| Domaine | Choix |
|---|---|
| UI | Flutter 3.41 + Material 3 |
| State | Riverpod 2 (StateNotifier + Provider.family) |
| Base de données | Drift + SQLCipher (clé hex 32B) |
| KDF | Argon2id (m=64 MiB, t=3, p=1, isolate Dart) |
| Chiffrement par champ | AES-256-GCM via `cryptography_flutter` (BoringSSL JNI) |
| Biométrie | BiometricPrompt + clé Keystore hardware-backed (`setInvalidatedByBiometricEnrollment`) |
| Sauvegardes | Format propriétaire **HTBK1** (magic + en-tête JSON + AAD AES-GCM + Phase A/B atomique avec recovery) |
| Recherche | FTS5 SQLite (uniquement métadonnées non sensibles) |
| Notifications | `flutter_local_notifications` + AlarmManager exact (pas de FCM, pas de Firebase) |
| Calendrier | `device_calendar` (pont système optionnel) |
| Plateforme | Android 8+ (minSdk 26) — téléphone et tablette |
| Langues | FR / EN |
| Licence | Apache 2.0 |

## Architecture

```
lib/
├── core/            theme, errors, providers, auto-lock
├── data/
│   ├── db/          tables Drift, migrations versionnées
│   ├── repositories/ accès domaine
│   ├── services/    backup HTBK1, notifications, RGPD export, search…
│   └── vault/       HealthVault + FieldCrypto + BiometricBridge
├── features/
│   ├── lock/        setup + déverrouillage hybride passphrase/biométrie
│   ├── home/        tableau de bord
│   ├── clients/ animals/ sessions/ agenda/
│   ├── attachments/ pièces jointes chiffrées
│   ├── backup/      sauvegarde / restauration .htbk
│   ├── about/       page « À propos » (PackageInfo)
│   ├── legal/       documents légaux (FR/EN)
│   └── settings/
├── utils/           atomic_write, ephemeral_cache, image_bounds…
├── widgets/         composants partagés (SensitiveTextField, ErrorView…)
└── l10n/            ARB (FR + EN)
```

## Développement

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test
flutter build apk --release
```

## Cadre juridique

Health Tech est un outil pour **praticien·ne·s du bien-être**, pas pour les professionnel·le·s de santé réglementé·e·s. Les pratiques d'accompagnement énergétique, magnétisme, géobiologie, ostéopathie animalière non-vétérinaire, etc. ne relèvent pas du Code de la santé publique : pas de diagnostic, pas de prescription, pas de substitution à un avis médical.

Chaque export PDF de séance porte la mention « bien-être, pas un avis médical » conforme.

Côté RGPD, l'utilisateur est responsable de traitement de son fichier client. L'éditeur (Patrice Haltaya, micro-entreprise SIRET 90437498000012) n'a aucun accès aux données — l'architecture en rend l'accès techniquement impossible.

## Licence

Apache 2.0 — voir [LICENSE](LICENSE).
