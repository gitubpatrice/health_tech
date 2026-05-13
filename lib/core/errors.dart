/// Typed application errors with stable, machine-readable codes.
///
/// UI layer turns codes into l10n strings via `errorView`. Repositories
/// and the vault throw subclasses of [HealthError] so the UI never has
/// to inspect `runtimeType` or string-match exception messages — anything
/// not matched falls back to a localised generic message.
sealed class HealthError implements Exception {
  const HealthError(this.code);
  final String code;

  @override
  String toString() => '$runtimeType($code)';
}

class VaultLockedError extends HealthError {
  const VaultLockedError() : super('vault_locked');
}

class VaultNotInitialisedError extends HealthError {
  const VaultNotInitialisedError() : super('vault_not_initialised');
}

class VaultAlreadyInitialisedError extends HealthError {
  const VaultAlreadyInitialisedError() : super('vault_already_initialised');
}

// (audit M17) `VaultWrongPassphraseError` et `StorageError` étaient
// déclarées mais jamais throw — `unlockWithPassphrase` retourne `false`
// pour une passphrase incorrecte (consommé par le LockScreen via
// `lockWrongPassphrase`) et aucun chemin n'émettait `StorageError`.
// Classes retirées en v1.5.4 pour ne pas garder de surface morte.

/// Trop d'échecs consécutifs sur la phrase secrète : un backoff exponentiel
/// est en cours. La UI affiche le délai restant et désactive le bouton de
/// déverrouillage.
class VaultLockedOutError extends HealthError {
  const VaultLockedOutError(this.remainingSeconds) : super('vault_locked_out');
  final int remainingSeconds;
}

class ValidationError extends HealthError {
  const ValidationError(super.code, this.field);
  final String field;
}

/// Pièce jointe refusée car son poids dépasse le plafond fixé dans
/// `AttachmentRepository.kMaxAttachmentBytes`.
/// (audit H6) Typé HealthError pour que `localiseError` produise un
/// message cohérent ; auparavant tombait sur `errorGeneric`.
class AttachmentTooLargeError extends HealthError {
  const AttachmentTooLargeError(this.size) : super('attachment_too_large');
  final int size;
}

/// Pièce jointe refusée : format inconnu ou image bombe (dimensions
/// déraisonnables détectées par `ImageBoundsProbe` avant tout decode).
/// La [reason] discrimine la cause pour permettre des messages distincts
/// côté UI (`image_format_unrecognised` vs `image_too_large`).
class AttachmentRejectedError extends HealthError {
  const AttachmentRejectedError(this.reason)
    : super('attachment_rejected_$reason');
  final String reason;
}
