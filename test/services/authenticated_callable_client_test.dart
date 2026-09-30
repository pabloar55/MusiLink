import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musi_link/services/authenticated_callable_client.dart';

class _PendingClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;

  @override
  void close() => closed = true;
}

void main() {
  final deadline = isA<FirebaseFunctionsException>().having(
    (error) => error.code,
    'code',
    'deadline-exceeded',
  );

  AuthenticatedCallableClient create({
    required http.Client Function() client,
    Future<String?> Function()? auth,
    Future<String?> Function()? appCheck,
    Duration timeout = const Duration(seconds: 30),
  }) => AuthenticatedCallableClient(
    projectId: 'test-project',
    region: 'europe-southwest1',
    getIdToken: auth ?? () async => 'auth-token',
    getAppCheckToken: appCheck ?? () async => 'app-check-token',
    createClient: client,
    timeout: timeout,
  );

  test('uses Auth and App Check without waiting for an FCM token', () async {
    final data = {
      'chatId': 'existing-retry-id',
      'name': 'Música 🎵',
      'participantIds': ['friend-1', 'friend-2'],
    };
    var requests = 0;
    final service = create(
      client: () => MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://europe-southwest1-test-project.cloudfunctions.net/createGroupChat',
        );
        expect(request.headers['Authorization'], 'Bearer auth-token');
        expect(request.headers['X-Firebase-AppCheck'], 'app-check-token');
        expect(
          request.headers.containsKey('Firebase-Instance-ID-Token'),
          isFalse,
        );
        expect(jsonDecode(request.body), {'data': data});
        return http.Response('{"data":{"chatId":"existing-retry-id"}}', 200);
      }),
    );
    await service.call('createGroupChat', data);
    await service.call('createGroupChat', data);
    expect(requests, 2);
  });

  test('preserves backend error codes and details', () async {
    final service = create(
      client: () => MockClient(
        (_) async => http.Response(
          '{"error":{"status":"RESOURCE_EXHAUSTED",'
          '"message":"Too many groups","details":{"retryAfter":60}}}',
          429,
        ),
      ),
    );
    await expectLater(
      service.call('createGroupChat', {}),
      throwsA(
        isA<FirebaseFunctionsException>()
            .having((error) => error.code, 'code', 'resource-exhausted')
            .having((error) => error.details, 'details', {'retryAfter': 60}),
      ),
    );
  });

  for (final missingToken in ['auth', 'app-check']) {
    test('does not send a request without $missingToken', () async {
      final service = create(
        auth: missingToken == 'auth' ? () async => null : null,
        appCheck: missingToken == 'app-check' ? () async => null : null,
        client: () => throw StateError('No request should be sent'),
      );
      await expectLater(
        service.call('createGroupChat', {}),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
    });
  }

  test('times out token preparation and never sends a late request', () async {
    final token = Completer<String?>();
    var sent = false;
    var appCheckRead = false;
    final service = create(
      auth: () => token.future,
      appCheck: () async {
        appCheckRead = true;
        return 'app-check-token';
      },
      timeout: Duration.zero,
      client: () {
        sent = true;
        return MockClient((_) async => http.Response('{"data":null}', 200));
      },
    );
    await expectLater(service.call('createGroupChat', {}), throwsA(deadline));
    token.complete('late-auth-token');
    await Future<void>.delayed(Duration.zero);
    expect(sent, isFalse);
    expect(appCheckRead, isFalse);
  });

  test('times out the HTTP request and closes its client', () async {
    final client = _PendingClient();
    final service = create(client: () => client, timeout: Duration.zero);
    await expectLater(service.call('createGroupChat', {}), throwsA(deadline));
    expect(client.closed, isTrue);
  });

  test('reports HTTP connection errors as unavailable', () async {
    final service = create(
      client: () =>
          MockClient((_) async => throw http.ClientException('Offline')),
    );
    await expectLater(
      service.call('createGroupChat', {}),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });

  for (final body in ['<html>Error</html>', '{}', '{"data":null}']) {
    test('rejects malformed or unsuccessful responses: $body', () async {
      final service = create(
        client: () => MockClient((_) async => http.Response(body, 500)),
      );
      await expectLater(
        service.call('createGroupChat', {}),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'internal',
          ),
        ),
      );
    });
  }
}
