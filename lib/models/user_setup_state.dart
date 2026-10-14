/// Pasos del alta completados por una cuenta. `deletionPending` es null
/// cuando no pudo comprobarse si la cuenta está en proceso de eliminación.
typedef UserSetupState = ({
  bool usernameSet,
  bool artistsSelected,
  bool onboardingDone,
  bool photoSetupDone,
  bool? deletionPending,
});

typedef FetchUserSetupState = Future<UserSetupState> Function(String uid);
typedef ReadCachedUserSetupState = UserSetupState? Function(String uid);
typedef PersistUserSetupState = Future<void> Function(
  String uid,
  UserSetupState state,
);

/// Estado del alta leído durante el arranque, antes de pintar la primera
/// pantalla.
class UserSetupBootstrapState {
  const UserSetupBootstrapState({
    required this.usernameSet,
    required this.artistsSelected,
    required this.onboardingDone,
    required this.photoSetupDone,
    this.deletionPending = false,
    this.setupStateKnown = true,
    this.userUid,
  });

  final bool usernameSet;
  final bool artistsSelected;
  final bool onboardingDone;
  final bool photoSetupDone;
  final bool deletionPending;
  final bool setupStateKnown;
  final String? userUid;
}
