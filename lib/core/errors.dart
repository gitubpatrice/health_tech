/// Typed application errors. Strings stay in the UI layer (l10n).
sealed class HealthError implements Exception {
  const HealthError(this.code);
  final String code;

  @override
  String toString() => '$runtimeType($code)';
}

class VaultLockedError extends HealthError {
  const VaultLockedError() : super('vault_locked');
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

class ValidationError extends HealthError {
  const ValidationError(super.code, this.field);
  final String field;
}
