/// CBOR Decoders
///
/// Utility functions for decoding CBOR to sync protocol messages.
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart';

/// Decodes CBOR bytes to a Map<String, dynamic>.
///
/// Throws [FormatException] if the bytes are not a valid CBOR map.
Map<String, dynamic> decodeFromCbor(Uint8List bytes) {
  final cborValue = cbor.decode(bytes);
  if (cborValue is! CborMap) {
    throw FormatException('Expected CBOR map, got ${cborValue.runtimeType}');
  }
  return _decodeMap(cborValue);
}

/// Decodes CBOR bytes to a List<Map<String, dynamic>>.
///
/// Throws [FormatException] if the bytes are not a valid CBOR array.
List<Map<String, dynamic>> decodeListFromCbor(Uint8List bytes) {
  final cborValue = cbor.decode(bytes);
  if (cborValue is! CborList) {
    throw FormatException('Expected CBOR array, got ${cborValue.runtimeType}');
  }
  return [
    for (final item in cborValue)
      if (item is CborMap)
        _decodeMap(item)
      else
        throw FormatException('Array item is not a map'),
  ];
}

/// Recursively converts a CborValue to a Dart value.
dynamic _decodeValue(CborValue value) {
  if (value is CborNull) {
    return null;
  } else if (value is CborBool) {
    return value.value;
  } else if (value is CborInt) {
    return value.toInt();
  } else if (value is CborFloat) {
    return value.value;
  } else if (value is CborString) {
    return value.toString();
  } else if (value is CborBytes) {
    return Uint8List.fromList(value.bytes);
  } else if (value is CborList) {
    return [for (final item in value) _decodeValue(item)];
  } else if (value is CborMap) {
    return _decodeMap(value);
  } else {
    throw FormatException('Unsupported CBOR type: ${value.runtimeType}');
  }
}

/// Decodes a CborMap to a Map<String, dynamic>.
Map<String, dynamic> _decodeMap(CborMap cborMap) {
  final result = <String, dynamic>{};
  for (final entry in cborMap.entries) {
    final key = entry.key;
    if (key is! CborString) {
      throw FormatException('Map key must be a string, got ${key.runtimeType}');
    }
    result[key.toString()] = _decodeValue(entry.value);
  }
  return result;
}

/// Safely extracts a string from a CBOR map.
String? extractString(CborMap map, String key) {
  final value = map[CborString(key)];
  if (value == null || value is CborNull) return null;
  if (value is CborString) return value.toString();
  throw FormatException(
      'Expected string for key "$key", got ${value.runtimeType}');
}

/// Safely extracts an int from a CBOR map.
int? extractInt(CborMap map, String key) {
  final value = map[CborString(key)];
  if (value == null || value is CborNull) return null;
  if (value is CborInt) return value.toInt();
  throw FormatException(
      'Expected int for key "$key", got ${value.runtimeType}');
}

/// Safely extracts a bool from a CBOR map.
bool? extractBool(CborMap map, String key) {
  final value = map[CborString(key)];
  if (value == null || value is CborNull) return null;
  if (value is CborBool) return value.value;
  throw FormatException(
      'Expected bool for key "$key", got ${value.runtimeType}');
}

/// Safely extracts bytes from a CBOR map.
Uint8List? extractBytes(CborMap map, String key) {
  final value = map[CborString(key)];
  if (value == null || value is CborNull) return null;
  if (value is CborBytes) return Uint8List.fromList(value.bytes);
  throw FormatException(
      'Expected bytes for key "$key", got ${value.runtimeType}');
}

/// Safely extracts a list from a CBOR map.
CborList? extractList(CborMap map, String key) {
  final value = map[CborString(key)];
  if (value == null || value is CborNull) return null;
  if (value is CborList) return value;
  throw FormatException(
      'Expected list for key "$key", got ${value.runtimeType}');
}

/// Safely extracts a nested map from a CBOR map.
CborMap? extractMap(CborMap map, String key) {
  final value = map[CborString(key)];
  if (value == null || value is CborNull) return null;
  if (value is CborMap) return value;
  throw FormatException(
      'Expected map for key "$key", got ${value.runtimeType}');
}
