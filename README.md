# Health Tech

Application Android (téléphone + tablette) de gestion d'agenda, clients humains, animaux et séances pour praticiens en soins énergétiques, Reiki et accompagnement bien-être.

**100 % local** : aucune donnée n'est envoyée sur Internet. Le verrouillage par phrase secrète et le chiffrement des données sensibles sont activés par défaut.

## Statut

`v0.7.0` — fonctionnel de bout en bout (clients, animaux, séances, agenda, pièces jointes, RGPD), audité. Voir [`SECURITY.md`](SECURITY.md) et [`PRIVACY.md`](PRIVACY.md).

## Pile technique

| Domaine | Choix |
|---|---|
| UI | Flutter 3.41 + Material 3 |
| State | Riverpod 2 |
| Base de données | Drift + SQLCipher |
| Crypto | Argon2id (KDF) + AES-256-GCM (chiffrement par champ) |
| Recherche | FTS5 (uniquement métadonnées non sensibles) |
| Calendrier | `device_calendar` (intégration Google Agenda local) |
| Plateforme | Android 8+ (minSdk 26) — téléphone et tablette |
| Langues | FR / EN |

## Architecture

```
lib/
├── core/            constantes, theme, errors, providers Riverpod
├── data/
│   ├── db/          tables Drift, migrations versionnées
│   └── vault/       HealthVault + FieldCrypto (AES-GCM)
├── features/        un dossier par domaine fonctionnel
│   ├── lock/        verrouillage / setup
│   ├── home/        tableau de bord
│   ├── clients/
│   ├── animals/
│   ├── sessions/
│   ├── agenda/
│   └── settings/
├── widgets/         composants partagés (AdaptiveScaffold, breakpoints)
└── l10n/            ARB (FR + EN)
```

Chaque feature est isolée — on peut l'éditer sans toucher aux autres. Le domaine ne dépend ni de Flutter ni de Drift.

## Développement

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test
flutter run
```

## Données sensibles

Les fiches santé humaines et animales sont des **données sensibles au sens de l'article 9 RGPD**. Conséquences :

- Chiffrement double : SQLCipher au niveau base + AES-GCM au niveau champ pour santé / comptes rendus.
- Pas de sauvegarde Android automatique (`allowBackup="false"`, exclusion `data_extraction_rules`).
- Avertissement médical présenté avant toute création de fiche.
- Droit à l'effacement : `purgeClient(id)` supprime physiquement et écrase.

## Licence

Apache 2.0.
