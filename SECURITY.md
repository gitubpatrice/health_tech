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
| **v1.5.1** | 2026-05-13 | Hotfix sync agenda Android — la v1.5.0 utilisait `CalendarContract.Events.SYNC_DATA1` pour le marqueur anti-collision, mais cette colonne est réservée par Android aux sync adapters (`CALLER_IS_SYNCADAPTER`) ; un app standard se prenait une `IllegalArgumentException` au moment de l'`insert`, et la sync échouait silencieusement. Remplacement par `CUSTOM_APP_PACKAGE` + `CUSTOM_APP_URI`, explicitement prévues pour les apps tierces. Le path "fallback temporel" couvre les events posés en v1.5.0. Aussi : message d'erreur explicite côté formulaire de séance (le `catch on Object` était silencieux). |
| **v1.5.0** | 2026-05-13 | Refactor lourd, 9 axes : (a) **PanicService** complet (wipe vault Keystore + DB SQLCipher + attachments + caches éphémères + restore_staging + image cache + prefs avec whitelist `auto_lock.minutes` seule) accessible dans Réglages avec double confirmation (token « EFFACER » à taper). (b) **DB v5** : nouvelle colonne `filename_encrypted` sur `attachments` (chiffrement au champ FieldCrypto), migration paresseuse des rows v4 à la première lecture, plus jamais de filename client en clair dans la DB. (c) Génération **PDF dans un isolate** via `compute()` (élimine le jank ~300 ms en main thread). (d) Recherche clients **FTS5** activé (10-50× plus rapide sur grand jeu) avec probe d'existence et fallback LIKE transparent, **debounce 250 ms** widget-level sur la search bar. (e) **EmptyState** widget unifié + adoption clients / agenda. (f) Markers agenda **colorés par AppointmentStatus** (cancelled/no_show = cs.error, confirmed = cs.tertiary, done = cs.outline). (g) Argon2id calibration **plafond porté de 6 à 10 itérations** (durcit le brute-force GPU sur devices récents). (h) **Détection de réutilisation passphrase** vault ↔ backup via fingerprint HMAC-SHA256 en mémoire (jamais persisté) — dialog d'avertissement avant export. (i) **UX agenda promue** : `SwitchListTile` dans `Card` visible juste sous le créneau horaire dans le formulaire de séance (helper text dynamique : on / off / déjà-lié / sera-retiré), et bouton « Ajouter à l'agenda » one-tap dans la vue détail quand non synchronisée. |
| **v1.4.6** | 2026-05-13 | Hardening audit 4 axes : (a) anti-fuite latérale Calendar — titre générique par défaut pour `bridge.push(appointment)`, marqueur `SYNC_DATA1=healthtech:<ownerId>` anti-collision data-loss inter-événement, fallback re-create si update touche 0 rows ; (b) cap dur bundle `.htbk` à l'import (256 MiB envelope + 384 MiB cumulé décompressé, anti zip-bomb) ; (c) `pBytes` Argon2id wipé en `finally` même si le worker throw ; (d) plus de dépendances `pointycastle` / `crypto` (non utilisées) ; (e) symétrie session ↔ appointment sur la case « Ajouter à l'agenda » (uncheck = retire l'event Calendar + efface IDs DB). Refresh timezone à chaque push (anti clock-skew voyage). |
| **v1.4.5** | 2026-05-12 | Synchronisation agenda automatique à la sauvegarde d'une séance (DB v4). |
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
