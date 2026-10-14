import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/terms_acceptance_controller.dart';

final termsAcceptanceControllerProvider = Provider<TermsAcceptanceController>((
  ref,
) {
  // El router conserva esta instancia: solo se observan dependencias estables.
  final service = ref.read(termsAcceptanceServiceProvider);
  final controller = TermsAcceptanceController(
    auth: ref.watch(firebaseAuthProvider),
    readCachedAcceptance: service.hasCachedAcceptance,
    refreshAcceptance: service.hasAcceptedCurrentVersion,
    submitAcceptance: service.submitAcceptance,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
