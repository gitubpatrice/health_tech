/// Typed application errors. Strings stay in the UI layer (l10n).
///
/// Roadmap: today the codebase still raises stdlib `StateError` /
/// `ArgumentError` in repositories and the vault. v0.9 will route them
/// through these typed variants and add an `errorView(BuildContext, Object)`
/// helper that maps `code → l10n string`. The class is kept here so callers
/// don't have to wait for that refactor before adopting it.
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
