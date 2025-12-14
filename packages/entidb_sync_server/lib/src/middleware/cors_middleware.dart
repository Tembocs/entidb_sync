/// CORS Middleware
///
/// Cross-Origin Resource Sharing middleware for browser clients.
library;

import 'package:shelf/shelf.dart';

/// Creates CORS middleware with configurable allowed origins.
Middleware createCorsMiddleware({
  List<String> allowedOrigins = const ['*'],
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Handle preflight OPTIONS request
      if (request.method == 'OPTIONS') {
        return Response.ok(
          null,
          headers: _corsHeaders(request, allowedOrigins),
        );
      }

      // Handle regular request
      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders(request, allowedOrigins));
    };
  };
}

Map<String, String> _corsHeaders(Request request, List<String> allowedOrigins) {
  final origin = request.headers['origin'];

  // Determine allowed origin
  String allowedOrigin;
  if (allowedOrigins.contains('*')) {
    allowedOrigin = '*';
  } else if (origin != null && allowedOrigins.contains(origin)) {
    allowedOrigin = origin;
  } else {
    allowedOrigin = allowedOrigins.isNotEmpty ? allowedOrigins.first : '*';
  }

  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers':
        'Authorization, Content-Type, X-Requested-With',
    'Access-Control-Max-Age': '86400',
  };
}
