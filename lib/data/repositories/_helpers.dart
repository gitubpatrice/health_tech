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
Future<Value<String?>> encryptOptional(
  FieldCrypto crypto,
  String plain,
) async {
  if (plain.isEmpty) return const Value<String?>(null);
  return Value<String?>(await crypto.encryptString(plain));
}
