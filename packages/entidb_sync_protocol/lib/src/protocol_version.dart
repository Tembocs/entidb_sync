/// Protocol Version
///
/// Defines the sync protocol version for compatibility checking.
library;

/// Current sync protocol version.
const int kProtocolVersion = 1;

/// Minimum supported protocol version for backward compatibility.
const int kMinSupportedVersion = 1;

/// Protocol version information.
class ProtocolVersion {
  /// Creates protocol version information.
  const ProtocolVersion({required this.current, required this.minSupported});

  /// Current version.
  final int current;

  /// Minimum supported version.
  final int minSupported;

  /// Default protocol version.
  static const ProtocolVersion v1 = ProtocolVersion(
    current: kProtocolVersion,
    minSupported: kMinSupportedVersion,
  );

  /// Checks if a version is compatible.
  bool isCompatible(int version) {
    return version >= minSupported && version <= current;
  }
}
