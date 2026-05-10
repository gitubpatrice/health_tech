import 'package:drift/drift.dart';

import '../vault/field_crypto.dart';

/// Encrypts [plain] when it is non-empty and returns it wrapped in a
/// [Value] ready to be assigned to an `encrypted: ...` companion column.
/// An empty plaintext is mapped to a NULL row value (i.e. the "absent"
/// state, distinct from "empty string encrypted").
///
/// Centralises the 7+ duplicated `if (x.isEmpty) Value(null) else
/// Value(await crypto.encryptString(x))` patterns previously scattered
/// across every repository.
Future<Value<String?>> encryptOptional(FieldCrypto crypto, String plain) async {
  if (plain.isEmpty) return const Value<String?>(null);
  return Value<String?>(await crypto.encryptString(plain));
}

/// Time-helpers used by every repository — centralised here so the
/// epoch/millisecond/seconds split (a long-standing source of off-by-1000
/// bugs in this codebase) lives in exactly one place.

/// `epoch_ms (int) → DateTime?` — null in, null out. Used for
/// `birthDateMs`, `consentRgpdAt`, etc.
DateTime? msToDate(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

/// `DateTime? → epoch_ms (int?)`.
int? dateToMs(DateTime? d) => d?.millisecondsSinceEpoch;

/// `epoch_seconds (int) → DateTime`. Used for `created_at` / `updated_at`
/// / `start_at` etc. — all the columns Drift stores as integer seconds.
DateTime secondsToDate(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

/// `DateTime → epoch_seconds (int)`. Inverse of [secondsToDate].
int dateToSeconds(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
