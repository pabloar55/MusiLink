import 'package:cloud_functions/cloud_functions.dart';
import 'package:musi_link/services/service_exceptions.dart';

enum ReportReason {
  spam('spam'),
  harassment('harassment'),
  sexualContent('sexual_content'),
  hateSpeech('hate_speech'),
  impersonation('impersonation'),
  other('other');

  const ReportReason(this.wireValue);

  final String wireValue;
}

class ModerationService {
  const ModerationService(this._functions);

  final FirebaseFunctions _functions;

  Future<bool> reportProfile({
    required String reportedUserId,
    required ReportReason reason,
  }) => _submit({
    'type': 'profile',
    'reason': reason.wireValue,
    'reportedUserId': reportedUserId,
  });

  Future<bool> reportMessage({
    required String chatId,
    required String messageId,
    required ReportReason reason,
  }) => _submit({
    'type': 'message',
    'reason': reason.wireValue,
    'chatId': chatId,
    'messageId': messageId,
  });

  Future<bool> _submit(Map<String, dynamic> payload) async {
    try {
      final result = await _functions
          .httpsCallable('submitModerationReport')
          .call<Map<String, dynamic>>(payload);
      return result.data['created'] == true;
    } catch (error, stack) {
      Error.throwWithStackTrace(toServiceException(error), stack);
    }
  }
}
