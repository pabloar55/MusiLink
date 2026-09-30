import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

/// Uses the callable protocol without the optional FCM registration token.
/// On Safari, acquiring that token can stall before the SDK starts its timeout.
/// Auth and App Check are still required and verified by the callable backend.
class AuthenticatedCallableClient {
  AuthenticatedCallableClient({
    required this.projectId,
    required this.region,
    required this._getIdToken,
    required this._getAppCheckToken,
    http.Client Function()? createClient,
    this.timeout = const Duration(seconds: 30),
  }) : _createClient = createClient ?? http.Client.new;

  final String projectId;
  final String region;
  final Duration timeout;
  final Future<String?> Function() _getIdToken;
  final Future<String?> Function() _getAppCheckToken;
  final http.Client Function() _createClient;

  Future<void> call(String name, Map<String, dynamic> data) async {
    http.Client? client;
    var expired = false;
    FirebaseFunctionsException deadline() => FirebaseFunctionsException(
      code: 'deadline-exceeded',
      message: 'Callable request timed out.',
    );
    void checkDeadline() {
      if (expired) throw deadline();
    }

    Future<void> invoke() async {
      final idToken = await _getIdToken();
      checkDeadline();
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Authentication is required.',
        );
      }
      final appCheckToken = await _getAppCheckToken();
      checkDeadline();
      if (appCheckToken == null || appCheckToken.isEmpty) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'App Check is required.',
        );
      }
      client = _createClient();
      final response = await client!.post(
        Uri.https('$region-$projectId.cloudfunctions.net', '/$name'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          'X-Firebase-AppCheck': appCheckToken,
        },
        body: jsonEncode({'data': data}),
      );
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Invalid callable response.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Invalid callable response.',
        );
      }
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        throw FirebaseFunctionsException(
          code: (error['status'] as String? ?? 'INTERNAL')
              .toLowerCase()
              .replaceAll('_', '-'),
          message: error['message'] as String? ?? 'Callable request failed.',
          details: error['details'],
        );
      }
      if (response.statusCode != 200 ||
          (!decoded.containsKey('data') && !decoded.containsKey('result'))) {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Invalid callable response.',
        );
      }
    }

    try {
      await invoke().timeout(
        timeout,
        onTimeout: () {
          expired = true;
          throw deadline();
        },
      );
    } on http.ClientException catch (error) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: error.message,
      );
    } finally {
      expired = true;
      client?.close();
    }
  }
}
