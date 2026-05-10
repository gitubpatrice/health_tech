import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Convention "cache éphémère" pour les opérations de partage / import.
///
/// Les plugins natifs Android matérialisent souvent les bytes dans le
/// répertoire `cache/` du paquet avant de les passer à un FileProvider :
///   - `share_plus` (Share.shareXFiles) → `cache/share_plus/`
///   - `printing` (Printing.sharePdf) → `cache/printing/`
///   - `file_picker` (avec `withData: true`) → `cache/file_picker/`
///
/// Le contenu de ces caches est :
/// - en clair (pour share_plus / printing : PDF de séance, ZIP RGPD)
/// - chiffré mais transitoire (pour file_picker : .htbk importé pour
///   restore — le bundle reste sur disque jusqu'à éviction LRU OS).
///
/// Sans ce service, les fichiers traînent jusqu'au prochain `cache/`
/// cleanup système (jours / semaines). Sur device perdu non rooté,
/// `adb pull cache/` récupère tout. Ce service durcit la fenêtre de
/// vie en proposant :
///   - [purgeOnBoot] appelé une fois au démarrage (lib/main.dart) →
///     wipe tout cache résiduel des sessions précédentes ;
///   - [scheduleSharePurge] appelé après un `Share.shareXFiles` →
///     wipe le fichier 2 minutes plus tard (laisse le temps à l'app
///     cible de consommer, mais pas assez pour que l'utilisateur le
///     redécouvre par hasard) ;
///   - [purgeFilePicker] appelé après chaque import de fichier OK ou
///     erreur.
class EphemeralCache {
  const EphemeralCache._();

  /// Wipe tous les caches transitoires connus. À appeler une fois au
  /// boot dans `main()` après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> purgeOnBoot() async {
    final cache = await getTemporaryDirectory();
    await _wipeDir(Directory(p.join(cache.path, 'share_plus')));
    await _wipeDir(Directory(p.join(cache.path, 'printing')));
    await _wipeDir(Directory(p.join(cache.path, 'file_picker')));
    // Le file_picker plugin expose lui-même une API officielle de purge
    // qui sait quels fichiers ont été produits par lui (best-effort
    // doublon du wipe ci-dessus, idempotent).
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } on Object {
      // best-effort : si le plugin n'a pas encore initialisé ses canaux
      // au boot (avant le runApp), on retombera sur le purge manuel.
    }
  }

  /// Wipe immédiat des fichiers déposés par file_picker (bytes copiés
  /// depuis le ContentProvider source). À appeler après un import
  /// d'attachment OU après un import de bundle .htbk.
  static Future<void> purgeFilePicker() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } on Object {
      // best-effort
    }
    final cache = await getTemporaryDirectory();
    await _wipeDir(Directory(p.join(cache.path, 'file_picker')));
  }

  /// Schedule une purge différée du cache `share_plus` / `printing`.
  /// 2 minutes laissent le temps à Gmail / Drive / Files de consommer
  /// le fichier passé via FileProvider, mais pas plus. Au-delà,
  /// l'utilisateur n'est probablement plus dans le flow et le fichier
  /// peut être détruit.
  static Future<void> scheduleSharePurge({
    Duration delay = const Duration(minutes: 2),
  }) async {
    await Future<void>.delayed(delay);
    final cache = await getTemporaryDirectory();
    await _wipeDir(Directory(p.join(cache.path, 'share_plus')));
    await _wipeDir(Directory(p.join(cache.path, 'printing')));
  }

  static Future<void> _wipeDir(Directory dir) async {
    if (!dir.existsSync()) return;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // best-effort : un file lock ne doit pas faire foirer le
            // reste du wipe.
          }
        }
      }
    } on FileSystemException {
      // best-effort
    }
  }
}
