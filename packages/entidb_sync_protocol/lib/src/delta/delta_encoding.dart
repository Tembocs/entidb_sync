/// Delta Encoding
///
/// Implements field-level diffing for efficient sync of large entities.
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:meta/meta.dart';

/// Type of delta operation.
enum DeltaOpType {
  /// Set a field to a new value.
  set,

  /// Remove a field.
  remove,

  /// Increment a numeric field.
  increment,

  /// Append to an array field.
  arrayAppend,

  /// Remove from an array field.
  arrayRemove,

  /// Replace entire entity (fallback).
  replace,
}

/// A single delta operation on an entity field.
@immutable
class DeltaOperation {
  /// Path to the field (dot-separated for nested fields).
  final String path;

  /// Type of operation.
  final DeltaOpType opType;

  /// New value (for set, increment, arrayAppend, arrayRemove).
  final CborValue? value;

  const DeltaOperation({required this.path, required this.opType, this.value});

  /// Creates a set operation.
  factory DeltaOperation.set(String path, CborValue value) {
    return DeltaOperation(path: path, opType: DeltaOpType.set, value: value);
  }

  /// Creates a remove operation.
  factory DeltaOperation.remove(String path) {
    return DeltaOperation(path: path, opType: DeltaOpType.remove);
  }

  /// Creates an increment operation.
  factory DeltaOperation.increment(String path, num delta) {
    return DeltaOperation(
      path: path,
      opType: DeltaOpType.increment,
      value: delta is int
          ? CborInt(BigInt.from(delta))
          : CborFloat(delta.toDouble()),
    );
  }

  /// Creates an array append operation.
  factory DeltaOperation.arrayAppend(String path, CborValue value) {
    return DeltaOperation(
      path: path,
      opType: DeltaOpType.arrayAppend,
      value: value,
    );
  }

  /// Creates an array remove operation.
  factory DeltaOperation.arrayRemove(String path, CborValue value) {
    return DeltaOperation(
      path: path,
      opType: DeltaOpType.arrayRemove,
      value: value,
    );
  }

  /// Serializes to CBOR map.
  CborMap toCbor() {
    final map = <CborValue, CborValue>{
      CborString('path'): CborString(path),
      CborString('op'): CborString(opType.name),
    };

    if (value != null) {
      map[CborString('value')] = value!;
    }

    return CborMap(map);
  }

  /// Deserializes from CBOR map.
  factory DeltaOperation.fromCbor(CborMap map) {
    return DeltaOperation(
      path: (map[CborString('path')] as CborString).toString(),
      opType: DeltaOpType.values.firstWhere(
        (t) => t.name == (map[CborString('op')] as CborString).toString(),
      ),
      value: map[CborString('value')],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeltaOperation &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          opType == other.opType;

  @override
  int get hashCode => Object.hash(path, opType);

  @override
  String toString() => 'DeltaOperation($opType, $path)';
}

/// A delta patch containing multiple operations.
@immutable
class DeltaPatch {
  /// Base entity version this delta applies to.
  final int baseVersion;

  /// List of delta operations.
  final List<DeltaOperation> operations;

  const DeltaPatch({required this.baseVersion, required this.operations});

  /// Whether this is an empty patch.
  bool get isEmpty => operations.isEmpty;

  /// Whether this is a full replacement (single replace operation).
  bool get isFullReplacement =>
      operations.length == 1 && operations.first.opType == DeltaOpType.replace;

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    final ops = operations.map((op) => op.toCbor()).toList();
    final map = CborMap({
      CborString('baseVersion'): CborInt(BigInt.from(baseVersion)),
      CborString('ops'): CborList(ops),
    });
    return Uint8List.fromList(cbor.encode(map));
  }

  /// Deserializes from CBOR bytes.
  factory DeltaPatch.fromBytes(Uint8List bytes) {
    final cborValue = cbor.decode(bytes);
    if (cborValue is! CborMap) {
      throw FormatException('Invalid DeltaPatch: expected CBOR map');
    }

    final baseVersion = (cborValue[CborString('baseVersion')] as CborInt)
        .toInt();
    final opsArray = cborValue[CborString('ops')] as CborList;
    final operations = opsArray
        .whereType<CborMap>()
        .map((m) => DeltaOperation.fromCbor(m))
        .toList();

    return DeltaPatch(baseVersion: baseVersion, operations: operations);
  }

  /// Creates a full replacement patch.
  factory DeltaPatch.fullReplacement(int baseVersion, CborValue fullEntity) {
    return DeltaPatch(
      baseVersion: baseVersion,
      operations: [
        DeltaOperation(
          path: '',
          opType: DeltaOpType.replace,
          value: fullEntity,
        ),
      ],
    );
  }

  @override
  String toString() =>
      'DeltaPatch(baseVersion: $baseVersion, ops: ${operations.length})';
}

/// Computes deltas between two CBOR entities.
class DeltaEncoder {
  /// Maximum depth for recursive diff.
  final int maxDepth;

  /// Threshold for switching to full replacement (ratio of changed fields).
  final double replacementThreshold;

  const DeltaEncoder({this.maxDepth = 10, this.replacementThreshold = 0.7});

  /// Computes a delta patch from [oldEntity] to [newEntity].
  ///
  /// Returns null if entities are identical.
  DeltaPatch? computeDelta({
    required Uint8List? oldEntityCbor,
    required Uint8List newEntityCbor,
    required int baseVersion,
  }) {
    if (oldEntityCbor == null) {
      // No previous version, must be full replacement
      return DeltaPatch.fullReplacement(
        baseVersion,
        cbor.decode(newEntityCbor),
      );
    }

    final oldValue = cbor.decode(oldEntityCbor);
    final newValue = cbor.decode(newEntityCbor);

    if (_cborEquals(oldValue, newValue)) {
      return null; // No changes
    }

    if (oldValue is! CborMap || newValue is! CborMap) {
      // Non-map entities get full replacement
      return DeltaPatch.fullReplacement(baseVersion, newValue);
    }

    final operations = <DeltaOperation>[];
    _diffMaps(oldValue, newValue, '', operations, 0);

    if (operations.isEmpty) {
      return null;
    }

    // Check if too many changes - switch to full replacement
    // Use max of old and new field counts to handle deletions properly
    final oldFieldCount = _countFields(oldValue);
    final newFieldCount = _countFields(newValue);
    final totalFields = oldFieldCount > newFieldCount
        ? oldFieldCount
        : newFieldCount;
    final changedFields = operations.length;
    if (totalFields > 0 && changedFields / totalFields > replacementThreshold) {
      return DeltaPatch.fullReplacement(baseVersion, newValue);
    }

    return DeltaPatch(baseVersion: baseVersion, operations: operations);
  }

  void _diffMaps(
    CborMap oldMap,
    CborMap newMap,
    String prefix,
    List<DeltaOperation> operations,
    int depth,
  ) {
    if (depth >= maxDepth) {
      // Too deep, replace entire subtree
      operations.add(DeltaOperation.set(prefix, newMap));
      return;
    }

    // Convert keys to strings for reliable comparison
    final oldKeyStrings = <String, CborValue>{};
    for (final key in oldMap.keys) {
      oldKeyStrings[_keyToString(key)] = key;
    }

    final newKeyStrings = <String, CborValue>{};
    for (final key in newMap.keys) {
      newKeyStrings[_keyToString(key)] = key;
    }

    // Removed keys
    for (final keyStr in oldKeyStrings.keys) {
      if (!newKeyStrings.containsKey(keyStr)) {
        final path = _makePath(prefix, keyStr);
        operations.add(DeltaOperation.remove(path));
      }
    }

    // Added or modified keys
    for (final entry in newKeyStrings.entries) {
      final keyStr = entry.key;
      final newKey = entry.value;
      final path = _makePath(prefix, keyStr);
      final newValue = newMap[newKey];

      if (!oldKeyStrings.containsKey(keyStr)) {
        // New key
        operations.add(DeltaOperation.set(path, newValue!));
        continue;
      }

      final oldKey = oldKeyStrings[keyStr]!;
      final oldValue = oldMap[oldKey];
      if (_cborEquals(oldValue, newValue)) {
        continue; // Unchanged
      }

      // Recursively diff maps
      if (oldValue is CborMap && newValue is CborMap) {
        _diffMaps(oldValue, newValue, path, operations, depth + 1);
      } else if (oldValue is CborList && newValue is CborList) {
        // Arrays are replaced entirely for simplicity
        operations.add(DeltaOperation.set(path, newValue));
      } else {
        operations.add(DeltaOperation.set(path, newValue!));
      }
    }
  }

  String _makePath(String prefix, String key) {
    if (prefix.isEmpty) return key;
    return '$prefix.$key';
  }

  String _keyToString(CborValue key) {
    if (key is CborString) return key.toString();
    if (key is CborInt) return key.toInt().toString();
    return key.toString();
  }

  int _countFields(CborMap map) {
    int count = map.length;
    for (final value in map.values) {
      if (value is CborMap) {
        count += _countFields(value);
      }
    }
    return count;
  }

  bool _cborEquals(CborValue? a, CborValue? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.runtimeType != b.runtimeType) return false;

    if (a is CborInt && b is CborInt) {
      return a.toInt() == b.toInt();
    }
    if (a is CborFloat && b is CborFloat) {
      return a.value == b.value;
    }
    if (a is CborString && b is CborString) {
      return a.toString() == b.toString();
    }
    if (a is CborBool && b is CborBool) {
      return a.value == b.value;
    }
    if (a is CborBytes && b is CborBytes) {
      return _bytesEqual(a.bytes, b.bytes);
    }
    if (a is CborList && b is CborList) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_cborEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is CborMap && b is CborMap) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!_cborEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is CborNull && b is CborNull) return true;

    return false;
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Applies delta patches to entities.
class DeltaDecoder {
  const DeltaDecoder();

  /// Applies a delta patch to an entity.
  ///
  /// Returns the updated entity as CBOR bytes.
  Uint8List applyDelta({
    required Uint8List baseCbor,
    required DeltaPatch patch,
  }) {
    var entity = cbor.decode(baseCbor);

    for (final op in patch.operations) {
      entity = _applyOperation(entity, op);
    }

    return Uint8List.fromList(cbor.encode(entity));
  }

  CborValue _applyOperation(CborValue entity, DeltaOperation op) {
    if (op.opType == DeltaOpType.replace) {
      return op.value!;
    }

    if (entity is! CborMap) {
      throw FormatException('Cannot apply delta to non-map entity');
    }

    final parts = op.path.split('.');
    return _applyAtPath(entity, parts, op);
  }

  CborMap _applyAtPath(CborMap map, List<String> path, DeltaOperation op) {
    if (path.isEmpty || (path.length == 1 && path[0].isEmpty)) {
      // Apply at root
      return _applyToMap(map, '', op);
    }

    final key = CborString(path[0]);
    final remaining = path.sublist(1);

    if (remaining.isEmpty) {
      // Apply to this key
      return _applyToMap(map, path[0], op);
    }

    // Recurse into nested map
    final nested = map[key];
    if (nested is! CborMap) {
      throw FormatException('Path ${path[0]} is not a map');
    }

    final updated = _applyAtPath(nested, remaining, op);
    final newMap = <CborValue, CborValue>{};
    for (final entry in map.entries) {
      newMap[entry.key] = entry.value;
    }
    newMap[key] = updated;
    return CborMap(newMap);
  }

  CborMap _applyToMap(CborMap map, String key, DeltaOperation op) {
    final newMap = <CborValue, CborValue>{};
    for (final entry in map.entries) {
      newMap[entry.key] = entry.value;
    }
    final cborKey = CborString(key);

    switch (op.opType) {
      case DeltaOpType.set:
        newMap[cborKey] = op.value!;

      case DeltaOpType.remove:
        newMap.remove(cborKey);

      case DeltaOpType.increment:
        final current = newMap[cborKey];
        if (current is CborInt && op.value is CborInt) {
          newMap[cborKey] = CborInt(
            BigInt.from(current.toInt() + (op.value as CborInt).toInt()),
          );
        } else if (current is CborFloat || op.value is CborFloat) {
          final currentNum = current is CborInt
              ? current.toInt().toDouble()
              : (current as CborFloat).value;
          final deltaNum = op.value is CborInt
              ? (op.value as CborInt).toInt().toDouble()
              : (op.value as CborFloat).value;
          newMap[cborKey] = CborFloat(currentNum + deltaNum);
        }

      case DeltaOpType.arrayAppend:
        final current = newMap[cborKey];
        if (current is CborList) {
          newMap[cborKey] = CborList([...current.toList(), op.value!]);
        }

      case DeltaOpType.arrayRemove:
        final current = newMap[cborKey];
        if (current is CborList) {
          final list = current.toList();
          list.removeWhere((v) => _valuesEqual(v, op.value!));
          newMap[cborKey] = CborList(list);
        }

      case DeltaOpType.replace:
        // Should not happen at field level
        break;
    }

    return CborMap(newMap);
  }

  bool _valuesEqual(CborValue a, CborValue b) {
    // Simplified comparison
    return a.toString() == b.toString();
  }
}

/// Estimates the size savings of using delta encoding.
class DeltaSizeEstimator {
  /// Estimates size reduction ratio.
  ///
  /// Returns a value between 0 and 1 where 0 means no savings
  /// and 1 means maximum savings.
  static double estimateSavings({
    required Uint8List fullEntityCbor,
    required DeltaPatch patch,
  }) {
    final fullSize = fullEntityCbor.length;
    final patchSize = patch.toBytes().length;

    if (patchSize >= fullSize) return 0;
    return 1 - (patchSize / fullSize);
  }
}
