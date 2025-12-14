/// CBOR Encoders
///
/// Utility functions for encoding sync protocol messages to CBOR.
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart';

/// Encodes a Map<String, dynamic> to CBOR bytes.
///
/// Supports nested maps, lists, strings, integers, booleans, null, and Uint8List.
Uint8List encodeToCbor(Map<String, dynamic> data) {
  final cborValue = _encodeValue(data);
  return Uint8List.fromList(cbor.encode(cborValue));
}

/// Encodes a list of maps to CBOR bytes.
Uint8List encodeListToCbor(List<Map<String, dynamic>> list) {
  final cborArray = CborList([
    for (final item in list) _encodeValue(item),
  ]);
  return Uint8List.fromList(cbor.encode(cborArray));
}

/// Recursively converts a Dart value to a CborValue.
CborValue _encodeValue(dynamic value) {
  if (value == null) {
    return CborNull();
  } else if (value is bool) {
    return CborBool(value);
  } else if (value is int) {
    return CborInt(BigInt.from(value));
  } else if (value is double) {
    return CborFloat(value);
  } else if (value is String) {
    return CborString(value);
  } else if (value is Uint8List) {
    return CborBytes(value);
  } else if (value is List) {
    return CborList([for (final item in value) _encodeValue(item)]);
  } else if (value is Map<String, dynamic>) {
    return CborMap({
      for (final entry in value.entries)
        CborString(entry.key): _encodeValue(entry.value),
    });
  } else {
    throw ArgumentError(
        'Unsupported type for CBOR encoding: ${value.runtimeType}');
  }
}

/// Creates a CBOR map from string key-value pairs.
CborMap createCborMap(Map<String, CborValue> entries) {
  return CborMap({
    for (final entry in entries.entries) CborString(entry.key): entry.value,
  });
}

/// Helper to wrap common Dart types as CborValue.
extension CborValueHelpers on Object? {
  CborValue toCbor() => _encodeValue(this);
}
