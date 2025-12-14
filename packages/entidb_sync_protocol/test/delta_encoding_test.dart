/// Delta Encoding Tests
///
/// Tests for field-level diff and patch operations.
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('DeltaOperation', () {
    test('creates set operation', () {
      final op = DeltaOperation.set('name', CborString('Alice'));
      expect(op.path, equals('name'));
      expect(op.opType, equals(DeltaOpType.set));
      expect(op.value, isA<CborString>());
    });

    test('creates remove operation', () {
      final op = DeltaOperation.remove('oldField');
      expect(op.path, equals('oldField'));
      expect(op.opType, equals(DeltaOpType.remove));
      expect(op.value, isNull);
    });

    test('creates increment operation', () {
      final op = DeltaOperation.increment('counter', 5);
      expect(op.path, equals('counter'));
      expect(op.opType, equals(DeltaOpType.increment));
    });

    test('creates arrayAppend operation', () {
      final op = DeltaOperation.arrayAppend('tags', CborString('new-tag'));
      expect(op.path, equals('tags'));
      expect(op.opType, equals(DeltaOpType.arrayAppend));
    });

    test('creates arrayRemove operation', () {
      final op = DeltaOperation.arrayRemove('tags', CborString('old-tag'));
      expect(op.path, equals('tags'));
      expect(op.opType, equals(DeltaOpType.arrayRemove));
    });

    test('serializes to CBOR and back', () {
      final op = DeltaOperation.set('user.name', CborString('Bob'));
      final cborMap = op.toCbor();
      final restored = DeltaOperation.fromCbor(cborMap);

      expect(restored.path, equals(op.path));
      expect(restored.opType, equals(op.opType));
    });

    test('equality works correctly', () {
      final op1 = DeltaOperation.set('name', CborString('Alice'));
      final op2 = DeltaOperation.set('name', CborString('Alice'));
      final op3 = DeltaOperation.remove('name');

      expect(op1, equals(op2));
      expect(op1, isNot(equals(op3)));
    });
  });

  group('DeltaPatch', () {
    test('creates empty patch', () {
      final patch = DeltaPatch(baseVersion: 1, operations: []);
      expect(patch.isEmpty, isTrue);
      expect(patch.isFullReplacement, isFalse);
    });

    test('identifies full replacement', () {
      final patch = DeltaPatch.fullReplacement(
        1,
        CborMap({CborString('name'): CborString('Alice')}),
      );
      expect(patch.isFullReplacement, isTrue);
    });

    test('serializes to bytes and back', () {
      final patch = DeltaPatch(
        baseVersion: 5,
        operations: [
          DeltaOperation.set('name', CborString('Alice')),
          DeltaOperation.remove('oldField'),
          DeltaOperation.increment('count', 1),
        ],
      );

      final bytes = patch.toBytes();
      final restored = DeltaPatch.fromBytes(bytes);

      expect(restored.baseVersion, equals(5));
      expect(restored.operations.length, equals(3));
      expect(restored.operations[0].path, equals('name'));
      expect(restored.operations[1].opType, equals(DeltaOpType.remove));
    });
  });

  group('DeltaEncoder', () {
    const encoder = DeltaEncoder();

    test('returns null for identical entities', () {
      final entity = _createEntity({'name': 'Alice', 'age': 30});
      final patch = encoder.computeDelta(
        oldEntityCbor: entity,
        newEntityCbor: entity,
        baseVersion: 1,
      );
      expect(patch, isNull);
    });

    test('detects added field', () {
      final oldEntity = _createEntity({'name': 'Alice'});
      final newEntity = _createEntity({
        'name': 'Alice',
        'email': 'alice@example.com',
      });

      final patch = encoder.computeDelta(
        oldEntityCbor: oldEntity,
        newEntityCbor: newEntity,
        baseVersion: 1,
      );

      expect(patch, isNotNull);
      expect(patch!.operations.length, equals(1));
      expect(patch.operations[0].opType, equals(DeltaOpType.set));
      expect(patch.operations[0].path, equals('email'));
    });

    test('detects removed field', () {
      final oldEntity = _createEntity({'name': 'Alice', 'temp': 'value'});
      final newEntity = _createEntity({'name': 'Alice'});

      final patch = encoder.computeDelta(
        oldEntityCbor: oldEntity,
        newEntityCbor: newEntity,
        baseVersion: 1,
      );

      expect(patch, isNotNull);
      expect(
        patch!.operations.any((op) => op.opType == DeltaOpType.remove),
        isTrue,
      );
    });

    test('detects modified field', () {
      final oldEntity = _createEntity({'name': 'Alice', 'age': 30});
      final newEntity = _createEntity({'name': 'Alice', 'age': 31});

      final patch = encoder.computeDelta(
        oldEntityCbor: oldEntity,
        newEntityCbor: newEntity,
        baseVersion: 1,
      );

      expect(patch, isNotNull);
      expect(patch!.operations.length, equals(1));
      expect(patch.operations[0].path, equals('age'));
    });

    test('handles nested objects', () {
      final oldEntity = _createNestedEntity({
        'user': {'name': 'Alice', 'age': 30},
      });
      final newEntity = _createNestedEntity({
        'user': {'name': 'Alice', 'age': 31},
      });

      final patch = encoder.computeDelta(
        oldEntityCbor: oldEntity,
        newEntityCbor: newEntity,
        baseVersion: 1,
      );

      expect(patch, isNotNull);
      expect(patch!.operations[0].path, contains('user'));
    });

    test('falls back to full replacement for non-map entities', () {
      final oldEntity = Uint8List.fromList(cbor.encode(CborString('old')));
      final newEntity = Uint8List.fromList(cbor.encode(CborString('new')));

      final patch = encoder.computeDelta(
        oldEntityCbor: oldEntity,
        newEntityCbor: newEntity,
        baseVersion: 1,
      );

      expect(patch, isNotNull);
      expect(patch!.isFullReplacement, isTrue);
    });

    test('falls back to full replacement when too many changes', () {
      final oldEntity = _createEntity({'a': 1, 'b': 2, 'c': 3, 'd': 4});
      final newEntity = _createEntity({
        'a': 10,
        'b': 20,
        'c': 30,
        'd': 40,
        'e': 50,
      });

      const encoderLowThreshold = DeltaEncoder(replacementThreshold: 0.3);
      final patch = encoderLowThreshold.computeDelta(
        oldEntityCbor: oldEntity,
        newEntityCbor: newEntity,
        baseVersion: 1,
      );

      expect(patch, isNotNull);
      expect(patch!.isFullReplacement, isTrue);
    });

    test('creates full replacement for new entity', () {
      final newEntity = _createEntity({'name': 'Alice'});

      final patch = encoder.computeDelta(
        oldEntityCbor: null,
        newEntityCbor: newEntity,
        baseVersion: 0,
      );

      expect(patch, isNotNull);
      expect(patch!.isFullReplacement, isTrue);
    });
  });

  group('DeltaDecoder', () {
    const decoder = DeltaDecoder();

    test('applies set operation', () {
      final base = _createEntity({'name': 'Alice', 'age': 30});
      final patch = DeltaPatch(
        baseVersion: 1,
        operations: [DeltaOperation.set('name', CborString('Bob'))],
      );

      final result = decoder.applyDelta(baseCbor: base, patch: patch);
      final decoded = cbor.decode(result) as CborMap;

      expect(
        (decoded[CborString('name')] as CborString).toString(),
        equals('Bob'),
      );
    });

    test('applies remove operation', () {
      final base = _createEntity({'name': 'Alice', 'temp': 'remove-me'});
      final patch = DeltaPatch(
        baseVersion: 1,
        operations: [DeltaOperation.remove('temp')],
      );

      final result = decoder.applyDelta(baseCbor: base, patch: patch);
      final decoded = cbor.decode(result) as CborMap;

      expect(decoded[CborString('temp')], isNull);
      expect(decoded[CborString('name')], isNotNull);
    });

    test('applies increment operation', () {
      final base = _createEntity({'counter': 10});
      final patch = DeltaPatch(
        baseVersion: 1,
        operations: [DeltaOperation.increment('counter', 5)],
      );

      final result = decoder.applyDelta(baseCbor: base, patch: patch);
      final decoded = cbor.decode(result) as CborMap;

      expect((decoded[CborString('counter')] as CborInt).toInt(), equals(15));
    });

    test('applies full replacement', () {
      final base = _createEntity({'old': 'data'});
      final newData = CborMap({CborString('new'): CborString('data')});
      final patch = DeltaPatch.fullReplacement(1, newData);

      final result = decoder.applyDelta(baseCbor: base, patch: patch);
      final decoded = cbor.decode(result) as CborMap;

      expect(decoded[CborString('new')], isNotNull);
      expect(decoded[CborString('old')], isNull);
    });

    test('applies multiple operations', () {
      final base = _createEntity({'name': 'Alice', 'age': 30, 'temp': 'value'});
      final patch = DeltaPatch(
        baseVersion: 1,
        operations: [
          DeltaOperation.set('name', CborString('Bob')),
          DeltaOperation.set('age', CborInt(BigInt.from(31))),
          DeltaOperation.remove('temp'),
        ],
      );

      final result = decoder.applyDelta(baseCbor: base, patch: patch);
      final decoded = cbor.decode(result) as CborMap;

      expect(
        (decoded[CborString('name')] as CborString).toString(),
        equals('Bob'),
      );
      expect((decoded[CborString('age')] as CborInt).toInt(), equals(31));
      expect(decoded[CborString('temp')], isNull);
    });
  });

  group('DeltaSizeEstimator', () {
    test('estimates savings correctly', () {
      final largeEntity = _createEntity({
        'field1': 'value1',
        'field2': 'value2',
        'field3': 'value3',
        'field4': 'value4',
        'field5': 'value5',
      });

      final smallPatch = DeltaPatch(
        baseVersion: 1,
        operations: [DeltaOperation.set('field1', CborString('newValue1'))],
      );

      final savings = DeltaSizeEstimator.estimateSavings(
        fullEntityCbor: largeEntity,
        patch: smallPatch,
      );

      expect(savings, greaterThan(0));
      expect(savings, lessThanOrEqualTo(1));
    });

    test('returns zero for large patches', () {
      final smallEntity = _createEntity({'a': 1});
      final largePatch = DeltaPatch(
        baseVersion: 1,
        operations: List.generate(
          50,
          (i) => DeltaOperation.set('field$i', CborString('value$i')),
        ),
      );

      final savings = DeltaSizeEstimator.estimateSavings(
        fullEntityCbor: smallEntity,
        patch: largePatch,
      );

      expect(savings, equals(0));
    });
  });

  group('Round-trip encoding', () {
    test('encode and decode preserves entity', () {
      const encoder = DeltaEncoder();
      const decoder = DeltaDecoder();

      final original = _createEntity({
        'name': 'Alice',
        'age': 30,
        'email': 'alice@example.com',
      });

      final modified = _createEntity({
        'name': 'Alice',
        'age': 31,
        'email': 'alice@example.com',
        'phone': '123-456-7890',
      });

      final patch = encoder.computeDelta(
        oldEntityCbor: original,
        newEntityCbor: modified,
        baseVersion: 1,
      );

      expect(patch, isNotNull);

      final applied = decoder.applyDelta(baseCbor: original, patch: patch!);
      final appliedDecoded = cbor.decode(applied) as CborMap;
      final modifiedDecoded = cbor.decode(modified) as CborMap;

      expect(appliedDecoded.length, equals(modifiedDecoded.length));
      expect(
        (appliedDecoded[CborString('age')] as CborInt).toInt(),
        equals(31),
      );
      expect(appliedDecoded[CborString('phone')], isNotNull);
    });
  });
}

Uint8List _createEntity(Map<String, dynamic> data) {
  final map = <CborValue, CborValue>{};
  for (final entry in data.entries) {
    map[CborString(entry.key)] = _toCborValue(entry.value);
  }
  return Uint8List.fromList(cbor.encode(CborMap(map)));
}

Uint8List _createNestedEntity(Map<String, dynamic> data) {
  CborValue convert(dynamic value) {
    if (value is Map<String, dynamic>) {
      final map = <CborValue, CborValue>{};
      for (final entry in value.entries) {
        map[CborString(entry.key)] = convert(entry.value);
      }
      return CborMap(map);
    }
    return _toCborValue(value);
  }

  final map = <CborValue, CborValue>{};
  for (final entry in data.entries) {
    map[CborString(entry.key)] = convert(entry.value);
  }
  return Uint8List.fromList(cbor.encode(CborMap(map)));
}

CborValue _toCborValue(dynamic value) {
  if (value is String) return CborString(value);
  if (value is int) return CborInt(BigInt.from(value));
  if (value is double) return CborFloat(value);
  if (value is bool) return CborBool(value);
  throw ArgumentError('Unsupported type: ${value.runtimeType}');
}
