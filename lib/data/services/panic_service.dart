import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';
import '../../utils/ephemeral_cache.dart';
import '../vault/health_vault.dart';
import 'notification_service.dart';

/// Étape franchie pendant un panic-wipe. Sert au diagnostic et à
/// pouvoir reprendre proprement si l'OS tue le process à mi-parcours.
enum PanicStep {
  notificationsCancel,
  vaultDestroy,
  dbDelete,
  attachmentsWipe,
  cachesWipe,
  prefsWipe,
  imageCacheClear,
  done,
}

/// Effacement total et **irréversible** de toute trace Health Tech sur
/// l'appareil — clés Keystore, base SQLCipher, pièces jointes chiffrées,
/// caches éphémères, préférences applicatives, notifications planifiées
/// et bitmaps en RAM.
///
/// À distinguer du soft-delete (corbeille réversible) et du purge RGPD
/// par client (uniquement les données du client visé). Le panic-wipe est
/// la nuke globale — usage : appareil perdu / volé / changement de
/// propriétaire / situation de coercition. Aucun retour arrière.
///
/// **Ordre des étapes** : on coupe d'abord ce qui pourrait écrire (les
/// notifications planifiées), on rend la DB inutilisable côté crypto
/// (vault.destroy → invalide la VEK), puis on supprime physiquement les
/// fichiers, on vide le cache RAM (bitmaps Image.memory), enfin on vide
/// les prefs (via une **whitelist** des seules clés safe à conserver).
///
/// **Idempotent** : chaque étape tolère un état déjà nettoyé. Si l'OS
/// kill le process à mi-parcours, le prochain démarrage présente un coffre
/// vide (`vaultInitialisedProvider == false`) et l'UI invite à un nouveau
/// setup ; les fichiers résiduels seront balayés par `purgeOrphans` au
/// prochain unlock (qui n'arrivera jamais sans setup) — donc on s'assure
/// que **dbDelete et attachmentsWipe sont best-effort sur dirs entiers**,
/// pas dépendants d'une row DB.
class PanicService {
  PanicService({
    required this.vault,
    required this.notifications,
    SharedPreferences? prefs,
  }) : _prefsOverride = prefs;

  final HealthVault vault;
  final NotificationService notifications;

  /// Surcharge pour les tests. En prod on récupère l'instance via le
  /// singleton standard.
  final SharedPreferences? _prefsOverride;

  /// Liste fermée des clés `SharedPreferences` à PRÉSERVER au panic-wipe.
  /// Tout le reste est effacé. Garder cette liste **minuscule** : chaque
  /// entrée doit être justifiée comme « non identifiante et utile au
  /// premier lancement d'un nouveau coffre ».
  ///
  /// On préserve uniquement la durée d'auto-lock configurée par l'utilisateur,
  /// car son retrait forcerait la valeur par défaut (5 min) après un panic
  /// alors que le seul successeur légitime d'un panic-wipe est le même
  /// utilisateur qui re-setup son coffre — pas une fuite.
  /// **NE PAS ajouter** : tokens, derniers IDs, état UI, locales, ID
  /// téléphone — toute info qui permettrait de relier l'avant et l'après.
  static const Set<String> _kPrefsWhitelist = <String>{'auto_lock.minutes'};

  /// Exécute la séquence complète. [onStep] est notifié à chaque étape
  /// franchie — utile pour brancher un indicateur visuel ou un log. Une
  /// exception levée dans une étape **n'interrompt pas** la suite : le
  /// principe panic est « best-effort exhaustif », tout doit être tenté.
  Future<void> wipe({void Function(PanicStep step)? onStep}) async {
    await _safe(notifications.cancelAll);
    onStep?.call(PanicStep.notificationsCancel);

    await _safe(vault.destroy);
    onStep?.call(PanicStep.vaultDestroy);

    await _safe(_wipeDatabase);
    onStep?.call(PanicStep.dbDelete);

    await _safe(_wipeAttachments);
    onStep?.call(PanicStep.attachmentsWipe);

    await _safe(EphemeralCache.purgeOnBoot);
    onStep?.call(PanicStep.cachesWipe);

    await _safe(_wipePrefs);
    onStep?.call(PanicStep.prefsWipe);

    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    onStep?.call(PanicStep.imageCacheClear);

    onStep?.call(PanicStep.done);
  }

  Future<void> _wipeDatabase() async {
    final support = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(support.path, 'db'));
    if (dbDir.existsSync()) {
      // Best-effort : on supprime fichiers WAL / SHM + .db. delete(recursive)
      // tolère que la DB ait déjà été close + supprimée par vault.destroy.
      try {
        await dbDir.delete(recursive: true);
      } on FileSystemException {
        // ignore — un file lock ne doit pas faire échouer le wipe global.
      }
    }
  }

  Future<void> _wipeAttachments() async {
    final support = await getApplicationSupportDirectory();
    final attDir = Directory(p.join(support.path, 'attachments'));
    if (attDir.existsSync()) {
      try {
        await attDir.delete(recursive: true);
      } on FileSystemException {
        // ignore
      }
    }
    // Aussi tuer un éventuel staging de restore en cours (peut contenir
    // un vault.json en clair sous master key — la VEK vient juste d'être
    // détruite mais le sel KDF resterait lisible).
    final stagingDir = Directory(p.join(support.path, 'restore_staging'));
    if (stagingDir.existsSync()) {
      try {
        await stagingDir.delete(recursive: true);
      } on FileSystemException {
        // ignore
      }
    }
  }

  Future<void> _wipePrefs() async {
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toSet();
    for (final k in keys) {
      if (_kPrefsWhitelist.contains(k)) continue;
      await prefs.remove(k);
    }
  }

  /// Tolère qu'une étape throw : panic-wipe est best-effort exhaustif.
  Future<void> _safe(Future<void> Function() step) async {
    try {
      await step();
    } on Object {
      // ignore : l'étape est best-effort, la suivante doit s'exécuter.
    }
  }
}

/// Provider — instance unique par session déverrouillée. Recréé après un
/// panic-wipe quand l'utilisateur re-setup un coffre.
final panicServiceProvider = Provider<PanicService>((ref) {
  return PanicService(
    vault: ref.watch(vaultProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});
