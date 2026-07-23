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
  String get authErrorGoogleSignIn => 'No se pudo iniciar sesión con Google.';

  @override
  String get authErrorGoogleSignInGeneric =>
      'Error al iniciar sesión con Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'Este email ya está registrado con contraseña. Inicia sesión con email y contraseña.';

  @override
  String get authUsername => 'Nombre de usuario';

  @override
  String get authEnterUsername => 'Elige un nombre de usuario';

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
  String get discoverTitle => 'Descubrir personas';

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
  String get chatDeleteBody => 'Se eliminará esta conversación.';

  @override
  String get chatDeleteConfirm => 'Eliminar';

  @override
  String get chatDeleteCancel => 'Cancelar';

  @override
  String get chatDateToday => 'Hoy';

  @override
  String get chatDateYesterday => 'Ayer';

  @override
  String get statsTracks => 'Canciones';

  @override
  String get statsArtists => 'Artistas';

  @override
  String get statsGenres => 'Géneros';

  @override
  String get statsShortTerm => '4 semanas';

  @override
  String get statsMediumTerm => '6 meses';

  @override
  String get statsLongTerm => '1 año';

  @override
  String statsError(String error) {
    return 'Error: $error';
  }

  @override
  String get statsEditArtists => 'Editar artistas';

  @override
  String get statsNoData => 'No hay datos disponibles';

  @override
  String get statsOfflineCache => 'Sin conexión — mostrando datos guardados';

  @override
  String get statsStaleCache => 'Mostrando datos de hace más de 48 horas';

  @override
  String get statsOfflineNoData =>
      'Sin conexión y sin datos guardados.\nVisita esta pestaña con internet primero.';

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
  String artistSelectorSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artistas · cuantos más, mejor compatibilidad',
      one: '1 artista · cuantos más, mejor compatibilidad',
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
  String get artistSelectorStageHint =>
      'Añade más para mejorar tus recomendaciones';

  @override
  String get menuProfile => 'Mi perfil';

  @override
  String get menuAccountOptions => 'Opciones de cuenta';

  @override
  String get menuLightMode => 'Modo claro';

  @override
  String get menuDarkMode => 'Modo oscuro';

  @override
  String get menuSignOut => 'Cerrar sesión';

  @override
  String get signingOut => 'Cerrando sesión...';

  @override
  String discoverySharedArtists(String artists) {
    return 'Artistas en común: $artists';
  }

  @override
  String discoverySharedGenres(String genres) {
    return 'Géneros en común: $genres';
  }

  @override
  String discoveryCompatible(String score) {
    return '$score% compatible';
  }

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
  String get friendsAlreadyFriends => 'Ya son amigos';

  @override
  String get profileAddFriend => 'Añadir amigo';

  @override
  String get dailySongTitle => 'Canción del día';

  @override
  String get dailySongYourTitle => 'Tu canción del día';

  @override
  String get dailySongChoose => 'Elegir tu canción del día';

  @override
  String dailySongBy(String artist) {
    return 'de $artist';
  }

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
  String get photoSetupUploading => 'Subiendo...';

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
      'En iPhone, abre MusiLink desde Safari, pulsa Compartir y selecciona «Añadir a pantalla de inicio». Después, abre la app desde su icono.';

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
  String get deletingAccount => 'Eliminando cuenta...';

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
  String get privacyTitle => 'Política de privacidad';

  @override
  String get privacyLastUpdated => 'Última actualización: 5 de mayo de 2026';

  @override
  String get privacyS1Title => '1. Responsable del tratamiento';

  @override
  String get privacyS1Body =>
      'MusiLink es desarrollada y operada por Pablo Armas (armasp80@gmail.com), con domicilio en España. Pablo Armas actúa como responsable del tratamiento de tus datos personales conforme al Reglamento (UE) 2016/679 (RGPD).';

  @override
  String get privacyS2Title => '2. Datos que recogemos';

  @override
  String get privacyS2Body =>
      'Recogemos y tratamos los siguientes datos personales:\n\n• Datos de cuenta: nombre, dirección de correo electrónico, foto de perfil e identificadores de inicio de sesión (mediante correo/contraseña o Google).\n\n• Datos de perfil musical: artistas principales que eliges, géneros principales inferidos, canción del día y canciones compartidas.\n\n• Datos sociales: mensajes, solicitudes de amistad y reacciones con emojis.\n\n• Datos técnicos: informes de fallos recopilados por Firebase Crashlytics y eventos de uso recopilados por Firebase Analytics.';

  @override
  String get privacyS3Title => '3. Cómo usamos tus datos';

  @override
  String get privacyS3Body =>
      'Tus datos se tratan con las siguientes finalidades:\n\n• Prestación del servicio (cuenta, compatibilidad musical, descubrimiento, chat). Base legal: ejecución de un contrato (art. 6.1.b RGPD).\n\n• Funciones de perfil musical: mostrar y comparar el gusto musical que has seleccionado. Base legal: ejecución de un contrato (art. 6.1.b RGPD).\n\n• Estabilidad de la app: diagnóstico de errores y fallos. Base legal: interés legítimo (art. 6.1.f RGPD).\n\n• Mejora de la app: comprender cómo se usa la app para mejorarla. Base legal: interés legítimo (art. 6.1.f RGPD).';

  @override
  String get privacyS4Title => '4. Servicios de terceros';

  @override
  String get privacyS4Body =>
      'Utilizamos los siguientes servicios de terceros, sujetos a sus propias políticas de privacidad:\n\n• Google Firebase Firestore, Crashlytics y Analytics — Google LLC. Tus datos de perfil, mensajes y eventos de uso se almacenan en servidores en la región europea (europe-southwest1).\n\n• Google Firebase Storage — Google LLC. Las fotos de perfil se almacenan en servidores ubicados en Estados Unidos bajo cláusulas contractuales tipo (Art. 46 RGPD).\n\n• Cloud Functions — Google LLC. Tus datos de mensajes y solicitudes de amistad se procesan en servidores en la región europea (europe-southwest1).\n\n• Spotify y Last.fm. Se utilizan como proveedores de catálogo musical para búsqueda de artistas/canciones y sugerencias de artistas. No es necesario conectar una cuenta de Spotify.';

  @override
  String get privacyS5Title => '5. Conservación y eliminación de datos';

  @override
  String get privacyS5Body =>
      'No conservamos tus datos más allá del tiempo que uses la aplicación. Al eliminar tu cuenta mediante el botón \'Eliminar cuenta\' en Ajustes, borramos tus datos privados, foto de perfil, relaciones, solicitudes, tokens, preferencias y datos musicales. El perfil público se sustituye por un marcador anónimo para no romper referencias técnicas. Los mensajes que hayas enviado se eliminan de las conversaciones y tus reacciones se retiran; si una conversación queda vacía, se borra. Algunos registros técnicos, informes de fallos o datos analíticos conservados por Google pueden estar sujetos a las políticas de retención propias de Google.';

  @override
  String get privacyS6Title => '6. Tus derechos';

  @override
  String get privacyS6Body =>
      'En virtud del RGPD, tienes los siguientes derechos:\n\n• Acceso: solicitar una copia de los datos que conservamos sobre ti.\n• Rectificación: corregir datos inexactos o incompletos.\n• Supresión: eliminar tu cuenta y todos los datos asociados mediante el botón \'Eliminar cuenta\' en Ajustes.\n• Limitación: solicitar que limitemos el tratamiento de tus datos.\n• Portabilidad: recibir tus datos en un formato estructurado y legible por máquina.\n• Oposición: oponerte al tratamiento basado en interés legítimo.\n\nPara ejercer estos derechos, contacta en armasp80@gmail.com. También puedes presentar una reclamación ante la Agencia Española de Protección de Datos (AEPD) en www.aepd.es.';

  @override
  String get privacyS7Title => '7. Edad mínima';

  @override
  String get privacyS7Body =>
      'MusiLink está destinada a usuarios de 16 años en adelante. No recogemos conscientemente datos de personas menores de 16 años. Si crees que un menor nos ha facilitado datos personales, contacta en armasp80@gmail.com y los eliminaremos de inmediato.';

  @override
  String get privacyS8Title => '8. Seguridad';

  @override
  String get privacyS8Body =>
      'Aplicamos medidas técnicas y organizativas adecuadas para proteger tus datos personales frente a accesos no autorizados, pérdidas o alteraciones. Los datos se almacenan en Google Firebase, que aplica controles de seguridad estándar del sector.';

  @override
  String get privacyS9Title => '9. Contacto';

  @override
  String get privacyS9Body =>
      'Para cualquier consulta sobre esta Política de Privacidad o el tratamiento de tus datos, puedes contactarnos en:\n\nPablo Armas\narmasp80@gmail.com';

  @override
  String get privacyS10Title => '10. Transferencias internacionales de datos';

  @override
  String get privacyS10Body =>
      'Las fotos de perfil se almacenan en Google Firebase Storage, con servidores ubicados en Estados Unidos. Al usar la aplicación, autorizas explícitamente esta transferencia internacional de datos de imágenes. Google ha implementado las medidas técnicas y organizativas necesarias bajo las Cláusulas Contractuales Tipo aprobadas por la Comisión Europea (Art. 46 RGPD) para garantizar un nivel de protección adecuado equivalente al de la UE.\n\nTus datos personales, mensajes y datos de perfil musical se almacenan en servidores ubicados en la región europea (europe-southwest1), dentro de la UE.';

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
