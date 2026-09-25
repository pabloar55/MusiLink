// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get authTagline =>
      'Conecta con personas que comparten tus gustos musicales';

  @override
  String get authName => 'Nombre';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Contraseña';

  @override
  String get authEnterName => 'Introduce tu nombre';

  @override
  String get authEnterEmail => 'Introduce tu email';

  @override
  String get authInvalidEmail => 'Email no válido';

  @override
  String get authEnterPassword => 'Introduce tu contraseña';

  @override
  String get authMinChars => 'Mínimo 6 caracteres';

  @override
  String get authErrorEmailInUse => 'Este email ya está registrado.';

  @override
  String get authErrorInvalidEmail => 'Email no válido.';

  @override
  String get authErrorWeakPassword =>
      'La contraseña debe tener al menos 6 caracteres.';

  @override
  String get authErrorUserNotFound => 'No existe una cuenta con este email.';

  @override
  String get authErrorWrongPassword => 'Contraseña incorrecta.';

  @override
  String get authErrorInvalidCredential => 'Credenciales incorrectas.';

  @override
  String get authErrorTooManyRequests =>
      'Demasiados intentos. Espera un momento.';

  @override
  String authErrorGeneric(String code) {
    return 'Error de autenticación ($code).';
  }

  @override
  String get authSignIn => 'Iniciar sesión';

  @override
  String get authCreateAccount => 'Crear cuenta';

  @override
  String get authOr => 'o';

  @override
  String get authContinueGoogle => 'Continuar con Google';

  @override
  String get authNoAccount => '¿No tienes cuenta?';

  @override
  String get authHaveAccount => '¿Ya tienes cuenta?';

  @override
  String get authRegister => 'Regístrate';

  @override
  String get authLogin => 'Inicia sesión';

  @override
  String get authForgotPassword => '¿Has olvidado tu contraseña?';

  @override
  String get authPasswordResetSent =>
      'Si este email tiene una cuenta con contraseña, te hemos enviado un enlace para cambiarla.';

  @override
  String get authErrorCouldNotAuth =>
      'No se pudo autenticar. Inténtalo de nuevo.';

  @override
  String get authErrorUnexpected => 'Error inesperado. Inténtalo de nuevo.';

  @override
  String get authErrorGoogleSignInGeneric =>
      'Error al iniciar sesión con Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'Este email ya está registrado con contraseña. Inicia sesión con email y contraseña.';

  @override
  String get authPrivacyLink => 'Política de privacidad';

  @override
  String get termsAcceptanceTitle => 'Términos y condiciones';

  @override
  String get termsAcceptanceIntro =>
      'Para continuar usando MusiLink, consulta y acepta los términos.';

  @override
  String termsAcceptanceVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get termsOpenDocument => 'Leer términos y condiciones';

  @override
  String get termsAcceptCheckbox =>
      'He leído y acepto los términos y condiciones de MusiLink.';

  @override
  String get termsAcceptAndContinue => 'Aceptar y continuar';

  @override
  String get termsAccepting => 'Aceptando…';

  @override
  String get termsSaveError =>
      'No se pudo guardar la aceptación. Inténtalo de nuevo.';

  @override
  String get termsOpenError => 'No se pudo abrir el enlace.';

  @override
  String get authUsername => 'Nombre de usuario';

  @override
  String get authUsernameHint => 'letras minúsculas, números y _';

  @override
  String get authUsernameTooShort => 'Al menos 3 caracteres';

  @override
  String get authUsernameTooLong => 'Máximo 20 caracteres';

  @override
  String get authUsernameInvalidChars => 'Solo letras, números y _';

  @override
  String get authUsernameTaken => 'Este nombre de usuario ya está en uso';

  @override
  String get authUsernameAvailable => 'Disponible';

  @override
  String get authUsernameChecking => 'Comprobando...';

  @override
  String get usernameSetupTitle => 'Elige tu nombre de usuario';

  @override
  String get usernameSetupSubtitle => 'Así te encontrarán otros en MusiLink.';

  @override
  String get usernameSetupButton => 'Continuar';

  @override
  String get discoverErrorLoading => 'Error al cargar descubrimiento';

  @override
  String get discoverNoUsers => 'No hay usuarios con datos musicales';

  @override
  String get discoverNoUsersHint =>
      'Cuando más usuarios creen su perfil musical, aparecerán aquí';

  @override
  String get navDiscover => 'Descubrir';

  @override
  String get navStats => 'Mi Top';

  @override
  String get navMessages => 'Mensajes';

  @override
  String get navFriends => 'Amigos';

  @override
  String get searchTitle => 'Buscar usuarios';

  @override
  String get searchHint => 'Nombre de usuario...';

  @override
  String get searchNoResults => 'No se encontraron usuarios';

  @override
  String get searchTypeToSearch => 'Escribe un nombre para buscar';

  @override
  String get profileTitle => 'Perfil musical';

  @override
  String get profileStartChat => 'Chatear';

  @override
  String get profileNoData => 'Este usuario aún no tiene datos musicales';

  @override
  String get profileTopArtists => 'Top Artistas';

  @override
  String get profileTopGenres => 'Top Géneros';

  @override
  String get profileCompatible => 'compatible';

  @override
  String get profileSharedArtists => 'Artistas en común';

  @override
  String get profileSharedGenres => 'Géneros en común';

  @override
  String get chatWriteMessage => 'Escribe un mensaje...';

  @override
  String get chatSearchSong => 'Buscar canción...';

  @override
  String get chatShareSong => 'Compartir canción';

  @override
  String get chatDeletedUser =>
      'Esta cuenta ha sido eliminada. Ya no puedes enviar mensajes.';

  @override
  String get chatBlockedCannotSend =>
      'Puedes ver el historial, pero no enviar mensajes en este chat.';

  @override
  String get chatNotFriendsCannotSend =>
      'Puedes ver el historial, pero solo los amigos pueden enviar mensajes en este chat.';

  @override
  String get chatSendFirst => 'Envía el primer mensaje';

  @override
  String get chatTypeToSearch => 'Escribe para buscar canciones';

  @override
  String get chatNoResults => 'Sin resultados';

  @override
  String get chatDeleteTitle => 'Eliminar conversación';

  @override
  String get chatDeleteConfirm => 'Eliminar';

  @override
  String get chatDeleteCancel => 'Cancelar';

  @override
  String get chatDateToday => 'Hoy';

  @override
  String get chatDateYesterday => 'Ayer';

  @override
  String get statsArtists => 'Artistas';

  @override
  String get statsGenres => 'Géneros';

  @override
  String get statsEditArtists => 'Editar artistas';

  @override
  String get statsNoData => 'No hay datos disponibles';

  @override
  String get socialNow => 'Ahora';

  @override
  String socialMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String socialDays(int days) {
    return '${days}d';
  }

  @override
  String get socialNoChats => 'No tienes conversaciones aún';

  @override
  String get socialNoChatsHint => 'Busca usuarios para empezar a chatear';

  @override
  String get socialErrorLoading => 'Error al cargar conversaciones';

  @override
  String get socialUser => 'Usuario';

  @override
  String get artistSelectorTitle => 'Mis Top Artistas';

  @override
  String artistSelectorSubtitle(int count, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de $max artistas seleccionados · arrastra para ordenar',
      one: '1 de $max artistas seleccionado · arrastra para ordenar',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorSearchHint => 'Buscar artistas...';

  @override
  String get artistSelectorContinue => 'Continuar';

  @override
  String artistSelectorContinueLocked(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Añade $remaining artistas más',
      one: 'Añade 1 artista más',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorNoResults => 'No se encontraron artistas';

  @override
  String get artistSelectorEmpty => 'Busca tus artistas favoritos para empezar';

  @override
  String get artistSelectorSuggested => 'Sugeridos';

  @override
  String get artistSelectorStageBasic => 'Básico';

  @override
  String get artistSelectorStageGood => 'Bueno';

  @override
  String get artistSelectorStageGreat => 'Genial';

  @override
  String get artistSelectorStageExpert => 'Experto';

  @override
  String get menuAccountOptions => 'Opciones de cuenta';

  @override
  String get menuSignOut => 'Cerrar sesión';

  @override
  String get signingOut => 'Cerrando sesión...';

  @override
  String get friendsReceivedRequests => 'Solicitudes recibidas';

  @override
  String get friendsSentRequests => 'Solicitudes enviadas';

  @override
  String get friendsMyFriends => 'Mis amigos';

  @override
  String get friendsAccept => 'Aceptar';

  @override
  String get friendsReject => 'Rechazar';

  @override
  String get friendsCancel => 'Cancelar';

  @override
  String get friendsSendRequest => 'Enviar solicitud';

  @override
  String get friendsRequestSent => 'Solicitud enviada';

  @override
  String get friendsNoRequests => 'No hay solicitudes pendientes';

  @override
  String get friendsNoFriends => 'Aún no tienes amigos';

  @override
  String get friendsNoFriendsHint => 'Busca usuarios para añadir amigos';

  @override
  String get friendsRemove => 'Eliminar amigo';

  @override
  String get friendsRemoveBody =>
      'Esta persona será eliminada de tu lista de amigos.';

  @override
  String get profileAddFriend => 'Añadir amigo';

  @override
  String get dailySongTitle => 'Canción del día';

  @override
  String get dailySongYourTitle => 'Tu canción del día';

  @override
  String get dailySongChoose => 'Elegir tu canción del día';

  @override
  String get discoverTabPeople => 'Descubrir personas';

  @override
  String get dailySongNone => 'Aún no has elegido tu canción del día';

  @override
  String get dailySongNoneHint => 'Comparte con los demás lo que escuchas hoy';

  @override
  String get dailySongFriendsTitle => 'Canciones de tus amigos';

  @override
  String get dailySongFriendsNone =>
      'Tus amigos aún no han elegido una canción del día';

  @override
  String get dailySongNoFriends =>
      'Añade amigos para ver sus canciones del día';

  @override
  String get dailySongSaveError =>
      'No se pudo publicar la canción. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get dailySongRefreshError =>
      'No se pudo actualizar desde el servidor. Se mantienen los datos anteriores.';

  @override
  String get dailySongLoadError =>
      'No se pudieron cargar las canciones del día.';

  @override
  String get dailySongReplyOutgoing => 'Has respondido a su canción del día';

  @override
  String get dailySongReplyIncoming => 'Ha respondido a tu canción del día';

  @override
  String get dailySongLikesTitle => 'Me gusta';

  @override
  String get dailySongNoLikes => 'Tu canción todavía no tiene me gusta.';

  @override
  String get dailySongLike => 'Me gusta';

  @override
  String get dailySongUnlike => 'Quitar me gusta';

  @override
  String get dailySongReply => 'Responder';

  @override
  String get dailySongReplyHint =>
      'Tu respuesta se enviará de forma privada al chat con este amigo.';

  @override
  String get dailySongReplySend => 'Enviar';

  @override
  String get dailySongReplySending => 'Enviando…';

  @override
  String get dailySongReplySent => 'Respuesta enviada al chat.';

  @override
  String get dailySongInteractionError =>
      'No se pudo guardar. Comprueba que seguís siendo amigos y la canción sigue disponible, e inténtalo de nuevo.';

  @override
  String get dailySongReplyTooLong => 'La respuesta es demasiado larga.';

  @override
  String get dailySongRetry => 'Reintentar';

  @override
  String get onboardingDiscoverTitle => 'Descubre personas';

  @override
  String get onboardingDiscoverDesc =>
      'MusiLink te conecta con personas que comparten tus gustos musicales. Descubre lo compatibles que sois según vuestros artistas favoritos.';

  @override
  String get onboardingProfileTitle => 'Construye tu perfil musical';

  @override
  String get onboardingProfileDesc =>
      'Añade los artistas que más escuchas. Cuantos más añadas, mejores serán tus matches y más personas descubrirás.';

  @override
  String get onboardingConnectTitle => 'Chatea, comparte, conecta';

  @override
  String get onboardingConnectDesc =>
      'Conecta con amigos, habla de música y comparte tu canción del día.';

  @override
  String get onboardingNext => 'Siguiente';

  @override
  String get onboardingGetStarted => '¡Vamos!';

  @override
  String get onboardingSkip => 'Saltar';

  @override
  String get photoSetupTitle => 'Añade una foto de perfil';

  @override
  String get photoSetupSubtitle =>
      'Que los demás sepan quién eres. Puedes cambiarla cuando quieras.';

  @override
  String get photoSetupChoose => 'Elegir foto';

  @override
  String get photoSetupChange => 'Cambiar foto';

  @override
  String get photoSetupContinue => 'Continuar';

  @override
  String get photoSetupSkip => 'Omitir por ahora';

  @override
  String get photoSetupGallery => 'Galería';

  @override
  String get photoSetupCamera => 'Cámara';

  @override
  String get photoSetupError => 'No se pudo subir la foto. Inténtalo de nuevo.';

  @override
  String get blockUserBlock => 'Bloquear usuario';

  @override
  String get blockUserUnblock => 'Desbloquear';

  @override
  String blockUserBlockConfirmTitle(String name) {
    return '¿Bloquear a $name?';
  }

  @override
  String get blockUserBlockConfirmBody =>
      'Se eliminará de tu lista de amigos y no aparecerá en tu descubrimiento.';

  @override
  String get blockUserBlockConfirm => 'Bloquear';

  @override
  String blockUserBlockedSnackbar(String name) {
    return '$name ha sido bloqueado';
  }

  @override
  String blockUserUnblockedSnackbar(String name) {
    return '$name ha sido desbloqueado';
  }

  @override
  String get reportProfileAction => 'Denunciar perfil';

  @override
  String get reportMessageAction => 'Denunciar mensaje';

  @override
  String reportProfileTitle(String name) {
    return 'Denunciar a $name';
  }

  @override
  String get reportMessageTitle => 'Denunciar mensaje';

  @override
  String get reportReasonPrompt => 'Selecciona el motivo de la denuncia:';

  @override
  String get reportReasonSpam => 'Spam o contenido engañoso';

  @override
  String get reportReasonHarassment => 'Acoso o amenazas';

  @override
  String get reportReasonSexualContent => 'Contenido sexual inapropiado';

  @override
  String get reportReasonHateSpeech => 'Odio o discriminación';

  @override
  String get reportReasonImpersonation => 'Suplantación de identidad';

  @override
  String get reportReasonOther => 'Otro motivo';

  @override
  String get reportSubmitted =>
      'Denuncia enviada. La revisaremos lo antes posible.';

  @override
  String get reportAlreadySubmitted => 'Ya habías denunciado este contenido.';

  @override
  String get reportSubmitError =>
      'No se pudo enviar la denuncia. Inténtalo de nuevo.';

  @override
  String get settingsPrivacy => 'Privacidad';

  @override
  String get settingsBlockedUsers => 'Usuarios bloqueados';

  @override
  String get blockedUsersTitle => 'Usuarios bloqueados';

  @override
  String get blockedUsersEmpty => 'No has bloqueado a ningún usuario';

  @override
  String get genericError => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get settingsNotifications => 'Notificaciones';

  @override
  String get settingsVibration => 'Vibración';

  @override
  String get settingsSound => 'Sonido';

  @override
  String get pushNotificationsTitle => 'No te pierdas ningún mensaje';

  @override
  String get pushNotificationsBody =>
      'Activa las notificaciones para recibir mensajes y solicitudes de amistad aunque MusiLink esté cerrada.';

  @override
  String get pushNotificationsEnable => 'Activar notificaciones';

  @override
  String get pushNotificationsInstallBody =>
      'En iPhone, abre MusiLink desde Safari, pulsa Compartir, después «Ver más» y selecciona «Añadir a pantalla de inicio». Después, abre la app desde su icono.';

  @override
  String get pushNotificationsBlockedBody =>
      'Las notificaciones están bloqueadas. Puedes activarlas en Ajustes del iPhone → Notificaciones → MusiLink.';

  @override
  String get pushNotificationsUnsupportedBody =>
      'Este navegador o dispositivo no admite notificaciones web.';

  @override
  String get pushNotificationsError =>
      'No se pudieron activar las notificaciones. Inténtalo de nuevo.';

  @override
  String get pwaInstallTitle => 'Instala MusiLink en tu iPhone';

  @override
  String get pwaInstallBody =>
      'Para recibir notificaciones y disfrutar de la experiencia completa:';

  @override
  String get pwaInstallStepMore => 'Pulsa Más (···), abajo a la derecha.';

  @override
  String get pwaInstallStepShare => 'Toca Compartir.';

  @override
  String get pwaInstallStepSeeMore => 'Pulsa «Ver más».';

  @override
  String get pwaInstallStepAdd => 'Selecciona «Añadir a pantalla de inicio».';

  @override
  String get pwaInstallStepOpen => 'Abre MusiLink desde su nuevo icono.';

  @override
  String get pwaInstallContinue => 'Continuar en Safari';

  @override
  String get settingsLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Política de privacidad';

  @override
  String get settingsDeleteAccount => 'Eliminar cuenta';

  @override
  String get deleteAccountBody =>
      'Esta acción eliminará permanentemente tu cuenta, tus mensajes, tus reacciones, tu foto, tus datos musicales y tu información de perfil. Esta acción no se puede deshacer.';

  @override
  String get deleteAccountConfirm => 'Eliminar';

  @override
  String get deletingAccount => 'Iniciando eliminación de la cuenta...';

  @override
  String get accountDeletionRequested =>
      'La eliminación de tu cuenta ha comenzado. Puedes cerrar la aplicación; el proceso continuará en segundo plano.';

  @override
  String get accountDeletionPending =>
      'Esta cuenta se está eliminando. Inténtalo de nuevo más tarde.';

  @override
  String get reauthTitle => 'Confirma tu identidad';

  @override
  String get reauthBody =>
      'Para eliminar tu cuenta, vuelve a introducir tu contraseña.';

  @override
  String get reauthConfirm => 'Confirmar';

  @override
  String get reauthWrongAccount =>
      'La cuenta seleccionada no está vinculada a esta app. Por favor, elige la cuenta correcta.';

  @override
  String get updateRequiredTitle => 'Actualización obligatoria';

  @override
  String get updateRequiredBody =>
      'Necesitas una nueva versión de MusiLink para continuar. Actualiza ahora para mantener tu cuenta y tus chats funcionando de forma segura.';

  @override
  String updateCurrentVersion(String version, int build) {
    return 'Versión instalada: $version ($build)';
  }

  @override
  String get updateNowButton => 'Actualizar ahora';

  @override
  String get updateRetryButton => 'Comprobar de nuevo';

  @override
  String get updateStoreOpenError =>
      'No hemos podido abrir la tienda. Comprueba tu conexión e inténtalo de nuevo.';
}
