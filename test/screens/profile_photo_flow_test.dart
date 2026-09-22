import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/profile_photo_upload_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/screens/account_settings_screen.dart';
import 'package:musi_link/screens/photo_setup_screen.dart';
import 'package:musi_link/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

class _MockImagePicker extends Mock implements ImagePicker {}

class _MockStorageService extends Mock implements StorageService {}

class _MockRouterNotifier extends Mock implements AppRouterNotifier {}

void main() {
  late MockFirebaseAuth auth;
  late MockUser user;
  late MockUserService users;
  late _MockImagePicker picker;
  late _MockStorageService storage;
  late _MockRouterNotifier router;
  late Completer<String?> upload;
  late ValueNotifier<Widget> screen;
  late Uint8List bytes;
  late XFile image;
  const url =
      'https://firebasestorage.googleapis.com/v0/b/'
      'musi-link-e7759.firebasestorage.app/o/'
      'profile_photos%2Falice?alt=media&token=new-photo';

  setUp(() {
    auth = MockFirebaseAuth();
    user = MockUser();
    users = MockUserService();
    picker = _MockImagePicker();
    storage = _MockStorageService();
    router = _MockRouterNotifier();
    screen = ValueNotifier<Widget>(const PhotoSetupScreen());
    bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
    );
    image = XFile.fromData(bytes, mimeType: 'image/png');
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('alice');
    when(() => user.email).thenReturn('alice@example.com');
    when(
      () => picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      ),
    ).thenAnswer((_) async => image);
    when(() => storage.uploadProfilePhoto('alice', image))
        .thenAnswer((_) => upload.future);
    when(() => users.updateSetupPhoto('alice', url)).thenAnswer((_) async {});
    when(() => users.updateProfile('alice', photoUrl: url))
        .thenAnswer((_) async {});
    when(() => router.setPhotoSetupDone()).thenAnswer((_) {
      screen.value = const Scaffold(body: Text('Next step'));
    });
  });

  Future<void> pumpApp(WidgetTester tester) async {
    upload = Completer<String?>();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          userServiceProvider.overrideWithValue(users),
          storageServiceProvider.overrideWithValue(storage),
          imagePickerProvider.overrideWithValue(picker),
          appRouterNotifierProvider.overrideWithValue(router),
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWith(
            (_) =>
                Stream.value(const AppUser(uid: 'alice', displayName: 'Alice')),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ValueListenableBuilder<Widget>(
            valueListenable: screen,
            builder: (_, value, _) => value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choosePhoto(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.camera));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'onboarding avanza antes de subir y guarda tras cerrar la pantalla',
    (tester) async {
      await pumpApp(tester);
      await choosePhoto(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('Next step'), findsOneWidget);
      expect(upload.isCompleted, isFalse);
      verifyNever(() => users.updateSetupPhoto('alice', url));
      upload.complete(url);
      await tester.pumpAndSettle();
      verify(() => users.updateSetupPhoto('alice', url)).called(1);
      verifyNever(() => users.updateProfile('alice', photoUrl: url));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('onboarding avisa si la subida falla después de avanzar', (
    tester,
  ) async {
    await pumpApp(tester);
    await choosePhoto(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    upload.completeError(StateError('Upload failed'));
    await tester.pumpAndSettle();
    expect(find.text('Next step'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajustes muestra la foto local y termina de guardar al salir', (
    tester,
  ) async {
    screen.value = const AccountSettingsScreen();
    await pumpApp(tester);
    await choosePhoto(tester);
    expect(upload.isCompleted, isFalse);
    final preview = tester.widget<Image>(find.byType(Image));
    expect((preview.image as MemoryImage).bytes, bytes);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    screen.value = const Scaffold(body: Text('Another screen'));
    await tester.pumpAndSettle();
    upload.complete(url);
    await tester.pumpAndSettle();
    verify(() => users.updateProfile('alice', photoUrl: url)).called(1);
    screen.value = const AccountSettingsScreen();
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajustes retira la vista previa si falla el guardado', (
    tester,
  ) async {
    screen.value = const AccountSettingsScreen();
    final save = Completer<void>();
    when(() => users.updateProfile('alice', photoUrl: url))
        .thenAnswer((_) => save.future);
    await pumpApp(tester);
    await choosePhoto(tester);
    upload.complete(url);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    save.completeError(StateError('Save failed'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no actualiza el perfil si cambia la sesión durante la subida', (
    tester,
  ) async {
    await pumpApp(tester);
    await choosePhoto(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    when(() => auth.currentUser).thenReturn(null);
    upload.complete(url);
    await tester.pumpAndSettle();
    verifyNever(() => users.updateSetupPhoto('alice', url));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajustes avisa de errores aunque se haya cerrado la pantalla', (
    tester,
  ) async {
    screen.value = const AccountSettingsScreen();
    await pumpApp(tester);
    await choosePhoto(tester);
    screen.value = const Scaffold(body: Text('Another screen'));
    await tester.pumpAndSettle();
    upload.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Another screen'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    verifyNever(() => users.updateProfile('alice', photoUrl: url));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalidar la subida al cerrar sesión no usa un ref descartado', (
    tester,
  ) async {
    await pumpApp(tester);
    await choosePhoto(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Next step')),
    );
    container.invalidate(profilePhotoUploadProvider);
    await tester.pump();
    upload.complete(url);
    await tester.pumpAndSettle();
    verifyNever(() => users.updateSetupPhoto('alice', url));
    expect(tester.takeException(), isNull);
  });
}
