import 'package:dio/dio.dart';

/// The HTTP client used for every playlist and guide request.
///
/// Dio has no timeouts by default, so a provider that stops answering mid-request
/// hangs the caller indefinitely — and the guide's two-endpoint fallback never
/// gets as far as trying its second endpoint. These values are deliberately
/// generous: they exist to turn a hang into a failure, not to police a slow
/// provider.
Dio createHttpClient() => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
