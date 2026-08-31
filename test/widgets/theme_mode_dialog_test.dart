import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/widgets/theme_mode_dialog.dart';

void main() {
  Future<ValueNotifier<ThemeMode?>> pumpAndOpenDialog(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    final result = ValueNotifier<ThemeMode?>(null);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await showThemeModeDialog(
                context: context,
                currentMode: ThemeMode.system,
                title: 'Tema',
                systemLabel: 'Sistema',
                lightLabel: 'Claro',
                darkLabel: 'Oscuro',
                cancelLabel: 'Cancelar',
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('usa un diálogo Material en Android', (tester) async {
    final result = await pumpAndOpenDialog(tester, TargetPlatform.android);
    addTearDown(result.dispose);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));

    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(result.value, ThemeMode.light);
  });

  testWidgets('usa un diálogo Cupertino en iOS', (tester) async {
    final result = await pumpAndOpenDialog(tester, TargetPlatform.iOS);
    addTearDown(result.dispose);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Oscuro'), findsOneWidget);

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(result.value, ThemeMode.dark);
  });
}
