/// JWT Authentication Middleware
///
/// Middleware for validating JWT tokens on protected sync endpoints.
library;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:shelf/shelf.dart';

/// Configuration for JWT authentication.
class JwtAuthConfig {
  /// Creates JWT authentication configuration.
  const JwtAuthConfig({
    required this.secret,
    this.issuer,
    this.audience,
    this.required = true,
    this.publicPaths = const ['/health', '/v1/version'],
  });

  /// Secret key for verifying JWT signatures.
  final String secret;

  /// JWT issuer to validate.
  final String? issuer;

  /// JWT audience to validate.
  final String? audience;

  /// Whether authentication is required (or optional).
  final bool required;

  /// List of paths that don't require authentication.
  final List<String> publicPaths;
}

/// Result of JWT validation.
class JwtValidationResult {
  const JwtValidationResult._({
    required this.isValid,
    this.error,
    this.payload,
    this.subject,
    this.deviceId,
    this.dbId,
  });

  /// Creates a successful validation result.
  factory JwtValidationResult.success({
    required Map<String, dynamic> payload,
    String? subject,
    String? deviceId,
    String? dbId,
  }) {
    return JwtValidationResult._(
      isValid: true,
      payload: payload,
      subject: subject,
      deviceId: deviceId,
      dbId: dbId,
    );
  }

  /// Creates a failed validation result.
  factory JwtValidationResult.failure(String error) {
    return JwtValidationResult._(isValid: false, error: error);
  }

  /// Whether the token is valid.
  final bool isValid;

  /// Error message if validation failed.
  final String? error;

  /// Decoded JWT payload if valid.
  final Map<String, dynamic>? payload;

  /// Subject (user ID) from the token.
  final String? subject;

  /// Device ID from the token (optional custom claim).
  final String? deviceId;

  /// Database ID from the token (optional custom claim).
  final String? dbId;
}

/// Creates JWT authentication middleware.
///
/// Validates JWT tokens in the Authorization header and adds
/// user context to the request for downstream handlers.
///
/// Usage:
/// ```dart
/// final config = JwtAuthConfig(secret: 'your-secret');
/// final handler = Pipeline()
///   .addMiddleware(createJwtAuthMiddleware(config))
///   .addHandler(yourHandler);
/// ```
Middleware createJwtAuthMiddleware(JwtAuthConfig config) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Skip authentication for public paths
      if (_isPublicPath(request.url.path, config.publicPaths)) {
        return innerHandler(request);
      }

      // Extract Authorization header
      final authHeader = request.headers['authorization'];
      if (authHeader == null || authHeader.isEmpty) {
        if (!config.required) {
          // Auth is optional, continue without user context
          return innerHandler(request);
        }
        return _unauthorizedResponse('Missing authorization header');
      }

      // Parse Bearer token
      if (!authHeader.startsWith('Bearer ')) {
        return _unauthorizedResponse('Invalid authorization format');
      }

      final token = authHeader.substring(7); // Remove 'Bearer ' prefix

      // Validate the token
      final result = validateJwt(
        token: token,
        secret: config.secret,
        issuer: config.issuer,
        audience: config.audience,
      );

      if (!result.isValid) {
        return _unauthorizedResponse(result.error ?? 'Invalid token');
      }

      // Add user context to request
      final updatedRequest = request.change(
        context: {
          ...request.context,
          'jwt': result.payload,
          'userId': result.subject,
          'deviceId': result.deviceId,
          'dbId': result.dbId,
        },
      );

      return innerHandler(updatedRequest);
    };
  };
}

/// Validates a JWT token.
///
/// Returns a [JwtValidationResult] indicating success or failure.
JwtValidationResult validateJwt({
  required String token,
  required String secret,
  String? issuer,
  String? audience,
}) {
  try {
    // Verify the token
    final jwt = JWT.verify(token, SecretKey(secret));

    // Validate issuer if specified
    if (issuer != null && jwt.issuer != issuer) {
      return JwtValidationResult.failure(
        'Invalid token issuer: expected $issuer',
      );
    }

    // Validate audience if specified
    if (audience != null && jwt.audience?.contains(audience) != true) {
      return JwtValidationResult.failure(
        'Invalid token audience: expected $audience',
      );
    }

    // Extract payload
    final payload = jwt.payload as Map<String, dynamic>? ?? {};

    return JwtValidationResult.success(
      payload: payload,
      subject: jwt.subject,
      deviceId: payload['deviceId'] as String?,
      dbId: payload['dbId'] as String?,
    );
  } on JWTExpiredException {
    return JwtValidationResult.failure('Token has expired');
  } on JWTInvalidException catch (e) {
    return JwtValidationResult.failure('Invalid token: ${e.message}');
  } on JWTNotActiveException {
    return JwtValidationResult.failure('Token is not yet active');
  } catch (e) {
    return JwtValidationResult.failure('Token validation failed: $e');
  }
}

/// Generates a JWT token for a user.
///
/// Useful for testing and token issuance.
///
/// - [subject]: User ID (stored in 'sub' claim).
/// - [secret]: Secret key for signing.
/// - [deviceId]: Optional device identifier.
/// - [dbId]: Optional database identifier.
/// - [issuer]: Optional token issuer.
/// - [audience]: Optional token audience.
/// - [expiresIn]: Token expiration duration (default: 24 hours).
String generateJwt({
  required String subject,
  required String secret,
  String? deviceId,
  String? dbId,
  String? issuer,
  String? audience,
  Duration expiresIn = const Duration(hours: 24),
}) {
  final payload = <String, dynamic>{
    if (deviceId != null) 'deviceId': deviceId,
    if (dbId != null) 'dbId': dbId,
  };

  final jwt = JWT(
    payload,
    subject: subject,
    issuer: issuer,
    audience: audience != null ? Audience([audience]) : null,
  );

  return jwt.sign(SecretKey(secret), expiresIn: expiresIn);
}

/// Checks if a path is in the public paths list.
bool _isPublicPath(String path, List<String> publicPaths) {
  // Normalize path
  final normalizedPath = path.startsWith('/') ? path : '/$path';

  for (final publicPath in publicPaths) {
    if (normalizedPath == publicPath ||
        normalizedPath.startsWith('$publicPath/')) {
      return true;
    }
  }

  return false;
}

/// Creates an unauthorized response with CBOR error body.
Response _unauthorizedResponse(String message) {
  final error = ErrorResponse.authenticationFailed(message: message);
  return Response(
    401,
    body: error.toBytes(),
    headers: {
      'Content-Type': 'application/cbor',
      'WWW-Authenticate': 'Bearer realm="sync"',
    },
  );
}

/// Extension to access JWT context from a request.
extension JwtRequestExtension on Request {
  /// Gets the JWT payload from the request context.
  Map<String, dynamic>? get jwtPayload =>
      context['jwt'] as Map<String, dynamic>?;

  /// Gets the user ID from the JWT.
  String? get userId => context['userId'] as String?;

  /// Gets the device ID from the JWT.
  String? get deviceId => context['deviceId'] as String?;

  /// Gets the database ID from the JWT.
  String? get dbId => context['dbId'] as String?;

  /// Whether the request is authenticated.
  bool get isAuthenticated => jwtPayload != null;
}
