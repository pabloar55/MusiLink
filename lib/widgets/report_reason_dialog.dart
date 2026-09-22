import 'package:flutter/material.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/services/moderation_service.dart';

Future<ReportReason?> showReportReasonDialog(
  BuildContext context, {
  required String title,
}) {
  final l10n = AppLocalizations.of(context)!;
  final labels = <ReportReason, String>{
    ReportReason.spam: l10n.reportReasonSpam,
    ReportReason.harassment: l10n.reportReasonHarassment,
    ReportReason.sexualContent: l10n.reportReasonSexualContent,
    ReportReason.hateSpeech: l10n.reportReasonHateSpeech,
    ReportReason.impersonation: l10n.reportReasonImpersonation,
    ReportReason.other: l10n.reportReasonOther,
  };

  return showDialog<ReportReason>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.reportReasonPrompt),
            const SizedBox(height: 8),
            for (final reason in ReportReason.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(labels[reason]!),
                onTap: () => Navigator.of(dialogContext).pop(reason),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.friendsCancel),
        ),
      ],
    ),
  );
}
