import 'dart:convert';

import 'package:drift/drift.dart';

class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(fromDb);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  @override
  String toSql(Map<String, dynamic> value) =>
      value.isEmpty ? '' : jsonEncode(value);
}

class JsonListConverter extends TypeConverter<List<String>, String> {
  const JsonListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <String>[];
    final decoded = jsonDecode(fromDb);
    return decoded is List ? decoded.cast<String>() : const <String>[];
  }

  @override
  String toSql(List<String> value) => value.isEmpty ? '' : jsonEncode(value);
}
