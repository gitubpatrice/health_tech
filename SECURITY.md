# Sécurité — Health Tech

## Modèle de menace

**Données protégées** : identité client, antécédents santé, comptes rendus de séance, photos d'animaux, documents joints (ordonnances, consentements).

**Adversaires considérés** :

1. **Téléphone perdu / volé, écran verrouillé** — protection : Keystore Android, Argon2id avec coût mémoire 64 MiB, FLAG_SECURE.
2. **Téléphone volé déverrouillé** — protection : verrouillage applicatif distinct (phrase secrète), auto-lock après inactivité.
3. **Application malveillante sur l'appareil** — protection : `allowBackup="false"`, `data_extraction_rules` exclut tout, pas d'export Intent permissif.
4. **Sauvegarde Android compromise** — protection : sauvegarde désactivée explicitement.
5. **Dump RAM via root** — protection partielle : VEK conservée le moins longtemps possible, wipe sur `lock()` et au niveau `FieldCrypto.dispose()`.

**Hors scope** : adversaire avec accès root persistant et patch du processus en mémoire.

## Architecture cryptographique

```
┌─────────────────────────┐
│  Phrase secrète user    │
└──────────┬──────────────┘
           │ Argon2id (mem=64MiB, t=3, p=1)
           ▼
   ┌──────────────────┐
   │   Master Key 32B │  (jamais persistée)
   └────────┬─────────┘
            │ AES-256-GCM (wrap)
            ▼
   ┌──────────────────┐
   │ Vault Encrypt Key│  (random 32B, persistée wrappée)
   └────────┬─────────┘
            │ AES-256-GCM (per field)
            ▼
   ┌──────────────────┐
   │ Champs sensibles │  (santé, comptes rendus, notes)
   └──────────────────┘

   ┌──────────────────┐
   │ SQLCipher (db)   │  (clé = hex(VEK))
   └──────────────────┘
```

## Décisions de conception

- **Deux clés (Master + VEK)** : permet le changement de phrase secrète sans réécrire les ciphertexts. Seule la clé wrappée change.
- **Chiffrement par champ AES-GCM** en plus de SQLCipher : si la base fuit en clair (cas extrême : dump après ouverture), les champs sensibles restent illisibles.
- **FTS5 indexe uniquement les métadonnées non sensibles** (nom, prénom, email, téléphone). Les comptes rendus et notes santé ne sont JAMAIS indexés FTS — sinon le contenu fuirait via les structures internes FTS.
- **`allowBackup=false`** : aucune copie cloud automatique.
- **FLAG_SECURE** : actif dès `onCreate` de MainActivity (pas seulement après le chargement de Flutter).

## Bonnes pratiques côté code

- Toute donnée sensible chiffrée au niveau champ DOIT passer par `FieldCrypto`.
- Aucune écriture en clair sur disque persistant. Cache export uniquement dans `cache/` (purgé au boot et sur `paused`).
- Atomic write systématique pour les fichiers (réutiliser `files_tech_core/atomic_write`).
- Lints stricts (`avoid_print`, `strict-casts`, `strict-inference`).

## Dépendances critiques

| Paquet | Rôle | Audité |
|---|---|---|
| `sqlcipher_flutter_libs` | Chiffrement DB | upstream Zetetic |
| `cryptography` | AES-GCM, Argon2id | dart team / community |
| `flutter_secure_storage` | Persistance clé wrappée | community, EncryptedSharedPreferences |
| `local_auth` | Biométrie | flutter team |

## Historique des versions

| Version | Date | Notes principales |
|---|---|---|
| **v1.4.3** | 2026-05-10 | Page « À propos » (version dynamique via PackageInfo). |
| **v1.4.2** | 2026-05-10 | Biométrie : suppression de la fenêtre 1h (alignement Bitwarden/Aegis). Cold-start et anti-rollback clock conservés. |
| **v1.4.1** | 2026-05-10 | UX : dialog « Import en cours » sur attachments, dropdown animal toujours visible (3 états). |
| **v1.4.0** | 2026-05-09 | Audit zéro-vuln pass : `EphemeralCache`, `SensitiveTextField` anti-Gboard, retry counter sauvegarde, tz refresh, Argon2id passphrase Uint8List wipable, `PaintingBinding.imageCache.clear` au lock. |
| **v1.3.x** | 2026-05-09 | Hybride passphrase / biométrie (Option D 1Password / Bitwarden), mode strict, AAD restore, ordre `_commitStaging` attachments → DB. |
| **v1.2.x** | 2026-05-09 | Lockout passphrase backoff, grace 2 min `onPause`/`onHide` (correction régression écran noir picker), Stopwatch monotonique. |
| **v1.1.x** | 2026-05-09 | KeystoreException distinguée (anti data-loss OTA Samsung), guard `_idFor` notification, `cancelAuthentication` Kotlin avant `deleteKey`. |
| **v1.0.0** | 2026-05-08 | Mise en production : 13 audit-fixes, 19 tests, 3 refactors archi, identité éditeur, hybride pass/bio. |

## Signaler une faille

Contact : security@files-tech.com (PGP à venir).
