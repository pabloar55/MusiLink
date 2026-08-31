import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<ThemeMode?> showThemeModeDialog({
  required BuildContext context,
  required ThemeMode currentMode,
  required String title,
  required String systemLabel,
  required String lightLabel,
  required String darkLabel,
  required String cancelLabel,
}) {
  final options = [
    (mode: ThemeMode.system, label: systemLabel),
    (mode: ThemeMode.light, label: lightLabel),
    (mode: ThemeMode.dark, label: darkLabel),
  ];

  return showAdaptiveDialog<ThemeMode>(
    context: context,
    builder: (dialogContext) {
      final platform = Theme.of(dialogContext).platform;
      final usesCupertino =
          platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

      if (usesCupertino) {
        return CupertinoAlertDialog(
          title: Text(title),
          actions: [
            for (final option in options)
              CupertinoDialogAction(
                isDefaultAction: option.mode == currentMode,
                onPressed: () => Navigator.of(dialogContext).pop(option.mode),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      child: option.mode == currentMode
                          ? const Icon(CupertinoIcons.check_mark, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(option.label),
                  ],
                ),
              ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(cancelLabel),
            ),
          ],
        );
      }

      return AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: RadioGroup<ThemeMode>(
          groupValue: currentMode,
          onChanged: (mode) {
            if (mode != null) Navigator.of(dialogContext).pop(mode);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                RadioListTile<ThemeMode>(
                  value: option.mode,
                  title: Text(option.label),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(cancelLabel),
          ),
        ],
      );
    },
  );
}
