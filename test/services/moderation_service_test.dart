import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/moderation_service.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseFunctions functions;
  late MockHttpsCallable callable;
  late MockHttpsCallableResult<Map<String, dynamic>> result;
  late ModerationService service;

  setUp(() {
    functions = MockFirebaseFunctions();
    callable = MockHttpsCallable();
    result = MockHttpsCallableResult<Map<String, dynamic>>();
    when(() => functions.httpsCallable('submitModerationReport'))
        .thenReturn(callable);
    when(() => result.data).thenReturn({'created': true});
    when(() => callable.call<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => result);
    service = ModerationService(functions);
  });

  test('envía una denuncia de perfil con contrato mínimo', () async {
    expect(
      await service.reportProfile(
        reportedUserId: 'bob',
        reason: ReportReason.impersonation,
      ),
      isTrue,
    );

    final payload =
        verify(() => callable.call<Map<String, dynamic>>(captureAny()))
                .captured
                .single
            as Map<String, dynamic>;
    expect(payload, {
      'type': 'profile',
      'reason': 'impersonation',
      'reportedUserId': 'bob',
    });
  });

  test('envía una denuncia de mensaje y refleja los duplicados', () async {
    when(() => result.data).thenReturn({'created': false});

    expect(
      await service.reportMessage(
        chatId: 'alice_bob',
        messageId: 'message-1',
        reason: ReportReason.harassment,
      ),
      isFalse,
    );

    final payload =
        verify(() => callable.call<Map<String, dynamic>>(captureAny()))
                .captured
                .single
            as Map<String, dynamic>;
    expect(payload, {
      'type': 'message',
      'reason': 'harassment',
      'chatId': 'alice_bob',
      'messageId': 'message-1',
    });
  });
}
