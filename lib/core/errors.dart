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

class VaultWrongPassphraseError extends HealthError {
  const VaultWrongPassphraseError() : super('vault_wrong_passphrase');
}

class VaultAlreadyInitialisedError extends HealthError {
  const VaultAlreadyInitialisedError() : super('vault_already_initialised');
}

class StorageError extends HealthError {
  const StorageError(super.code, this.cause);
  final Object cause;
}

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
