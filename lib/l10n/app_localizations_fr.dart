// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get authTagline =>
      'Connectez-vous avec des personnes qui partagent vos goûts musicaux';

  @override
  String get authName => 'Nom';

  @override
  String get authEmail => 'E-mail';

  @override
  String get authPassword => 'Mot de passe';

  @override
  String get authEnterName => 'Entrez votre nom';

  @override
  String get authEnterEmail => 'Entrez votre e-mail';

  @override
  String get authInvalidEmail => 'E-mail invalide';

  @override
  String get authEnterPassword => 'Entrez votre mot de passe';

  @override
  String get authMinChars => '6 caractères minimum';

  @override
  String get authErrorEmailInUse => 'Cet e-mail est déjà enregistré.';

  @override
  String get authErrorInvalidEmail => 'E-mail invalide.';

  @override
  String get authErrorWeakPassword =>
      'Le mot de passe doit contenir au moins 6 caractères.';

  @override
  String get authErrorUserNotFound => 'Aucun compte trouvé avec cet e-mail.';

  @override
  String get authErrorWrongPassword => 'Mot de passe incorrect.';

  @override
  String get authErrorInvalidCredential => 'Identifiants invalides.';

  @override
  String get authErrorTooManyRequests =>
      'Trop de tentatives. Veuillez patienter.';

  @override
  String authErrorGeneric(String code) {
    return 'Erreur d\'authentification ($code).';
  }

  @override
  String get authSignIn => 'Se connecter';

  @override
  String get authCreateAccount => 'Créer un compte';

  @override
  String get authOr => 'ou';

  @override
  String get authContinueGoogle => 'Continuer avec Google';

  @override
  String get authNoAccount => 'Vous n\'avez pas de compte ?';

  @override
  String get authHaveAccount => 'Vous avez déjà un compte ?';

  @override
  String get authRegister => 'S\'inscrire';

  @override
  String get authLogin => 'Se connecter';

  @override
  String get authForgotPassword => 'Mot de passe oublié ?';

  @override
  String get authPasswordResetSent =>
      'Si cet e-mail correspond à un compte avec mot de passe, nous avons envoyé un lien de réinitialisation.';

  @override
  String get authErrorCouldNotAuth =>
      'Impossible de s\'authentifier. Veuillez réessayer.';

  @override
  String get authErrorUnexpected => 'Erreur inattendue. Veuillez réessayer.';

  @override
  String get authErrorGoogleSignIn => 'Impossible de se connecter avec Google.';

  @override
  String get authErrorGoogleSignInGeneric =>
      'Erreur lors de la connexion avec Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'Cet e-mail est déjà enregistré avec un mot de passe. Veuillez vous connecter avec e-mail et mot de passe.';

  @override
  String get authUsername => 'Nom d\'utilisateur';

  @override
  String get authEnterUsername => 'Choisissez un nom d\'utilisateur';

  @override
  String get authUsernameHint => 'lettres minuscules, chiffres et _';

  @override
  String get authUsernameTooShort => 'Au moins 3 caractères';

  @override
  String get authUsernameTooLong => 'Max 20 caractères';

  @override
  String get authUsernameInvalidChars => 'Lettres, chiffres et _ seulement';

  @override
  String get authUsernameTaken => 'Ce nom d\'utilisateur est déjà pris';

  @override
  String get authUsernameAvailable => 'Disponible';

  @override
  String get authUsernameChecking => 'Vérification...';

  @override
  String get usernameSetupTitle => 'Choisissez votre nom d\'utilisateur';

  @override
  String get usernameSetupSubtitle =>
      'C\'est ainsi que les autres vous trouveront sur MusiLink.';

  @override
  String get usernameSetupButton => 'Continuer';

  @override
  String get discoverTitle => 'Découvrir des personnes';

  @override
  String get discoverErrorLoading =>
      'Erreur lors du chargement de la découverte';

  @override
  String get discoverNoUsers => 'Aucun utilisateur avec des données musicales';

  @override
  String get discoverNoUsersHint =>
      'Au fur et à mesure que d\'autres utilisateurs créent leur profil musical, ils apparaîtront ici';

  @override
  String get navDiscover => 'Découvrir';

  @override
  String get navStats => 'Mon Top';

  @override
  String get navMessages => 'Messages';

  @override
  String get navFriends => 'Amis';

  @override
  String get searchTitle => 'Rechercher des utilisateurs';

  @override
  String get searchHint => 'Nom d\'utilisateur...';

  @override
  String get searchNoResults => 'Aucun utilisateur trouvé';

  @override
  String get searchTypeToSearch => 'Tapez un nom pour rechercher';

  @override
  String get profileTitle => 'Profil musical';

  @override
  String get profileStartChat => 'Discuter';

  @override
  String get profileNoData =>
      'Cet utilisateur n\'a pas encore de données musicales';

  @override
  String get profileTopArtists => 'Top Artistes';

  @override
  String get profileTopGenres => 'Top Genres';

  @override
  String get profileCompatible => 'compatible';

  @override
  String get profileSharedArtists => 'Artistes en commun';

  @override
  String get profileSharedGenres => 'Genres en commun';

  @override
  String get chatWriteMessage => 'Écrire un message...';

  @override
  String get chatSearchSong => 'Rechercher une chanson...';

  @override
  String get chatShareSong => 'Partager une chanson';

  @override
  String get chatDeletedUser =>
      'Ce compte a été supprimé. Vous ne pouvez plus envoyer de messages.';

  @override
  String get chatBlockedCannotSend =>
      'Vous pouvez voir l\'historique, mais pas envoyer de messages dans ce chat.';

  @override
  String get chatNotFriendsCannotSend =>
      'Vous pouvez consulter l\'historique, mais seuls les amis peuvent envoyer des messages dans cette discussion.';

  @override
  String get chatSendFirst => 'Envoyez le premier message';

  @override
  String get chatTypeToSearch => 'Tapez pour rechercher des chansons';

  @override
  String get chatNoResults => 'Aucun résultat';

  @override
  String get chatDeleteTitle => 'Supprimer la conversation';

  @override
  String get chatDeleteBody => 'Cette conversation sera supprimée.';

  @override
  String get chatDeleteConfirm => 'Supprimer';

  @override
  String get chatDeleteCancel => 'Annuler';

  @override
  String get chatDateToday => 'Aujourd’hui';

  @override
  String get chatDateYesterday => 'Hier';

  @override
  String get statsTracks => 'Titres';

  @override
  String get statsArtists => 'Artistes';

  @override
  String get statsGenres => 'Genres';

  @override
  String get statsShortTerm => '4 semaines';

  @override
  String get statsMediumTerm => '6 mois';

  @override
  String get statsLongTerm => '1 an';

  @override
  String statsError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get statsEditArtists => 'Modifier les artistes';

  @override
  String get statsNoData => 'Aucune donnée disponible';

  @override
  String get statsOfflineCache => 'Hors ligne — données enregistrées affichées';

  @override
  String get statsStaleCache => 'Données de plus de 48 heures affichées';

  @override
  String get statsOfflineNoData =>
      'Pas de connexion et aucune donnée enregistrée.\nConsultez cet onglet en ligne d\'abord.';

  @override
  String get socialNow => 'Maintenant';

  @override
  String socialMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String socialDays(int days) {
    return '${days}j';
  }

  @override
  String get socialNoChats => 'Pas encore de conversations';

  @override
  String get socialNoChatsHint =>
      'Recherchez des utilisateurs pour commencer à discuter';

  @override
  String get socialErrorLoading =>
      'Erreur lors du chargement des conversations';

  @override
  String get socialUser => 'Utilisateur';

  @override
  String get artistSelectorTitle => 'Mes Top Artistes';

  @override
  String artistSelectorSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count artistes · plus vous en ajoutez, meilleure est la compatibilité',
      one: '1 artiste · plus vous en ajoutez, meilleure est la compatibilité',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorSearchHint => 'Rechercher des artistes...';

  @override
  String get artistSelectorContinue => 'Continuer';

  @override
  String artistSelectorContinueLocked(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Ajoutez $remaining artistes de plus',
      one: 'Ajoutez 1 artiste de plus',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorNoResults => 'Aucun artiste trouvé';

  @override
  String get artistSelectorEmpty =>
      'Recherchez vos artistes préférés pour commencer';

  @override
  String get artistSelectorSuggested => 'Suggérés';

  @override
  String get artistSelectorStageBasic => 'Basique';

  @override
  String get artistSelectorStageGood => 'Bien';

  @override
  String get artistSelectorStageGreat => 'Super';

  @override
  String get artistSelectorStageExpert => 'Expert';

  @override
  String get artistSelectorStageHint =>
      'Ajoutez-en plus pour améliorer vos recommandations';

  @override
  String get menuProfile => 'Mon profil';

  @override
  String get menuAccountOptions => 'Options du compte';

  @override
  String get menuLightMode => 'Mode clair';

  @override
  String get menuDarkMode => 'Mode sombre';

  @override
  String get menuSignOut => 'Se déconnecter';

  @override
  String get signingOut => 'Déconnexion en cours...';

  @override
  String discoverySharedArtists(String artists) {
    return 'Artistes en commun : $artists';
  }

  @override
  String discoverySharedGenres(String genres) {
    return 'Genres en commun : $genres';
  }

  @override
  String discoveryCompatible(String score) {
    return '$score% compatible';
  }

  @override
  String get friendsReceivedRequests => 'Demandes reçues';

  @override
  String get friendsSentRequests => 'Demandes envoyées';

  @override
  String get friendsMyFriends => 'Mes amis';

  @override
  String get friendsAccept => 'Accepter';

  @override
  String get friendsReject => 'Refuser';

  @override
  String get friendsCancel => 'Annuler';

  @override
  String get friendsSendRequest => 'Envoyer une demande';

  @override
  String get friendsRequestSent => 'Demande envoyée';

  @override
  String get friendsNoRequests => 'Aucune demande en attente';

  @override
  String get friendsNoFriends => 'Pas encore d\'amis';

  @override
  String get friendsNoFriendsHint =>
      'Recherchez des utilisateurs pour ajouter des amis';

  @override
  String get friendsRemove => 'Supprimer l\'ami';

  @override
  String get friendsRemoveBody =>
      'Cette personne sera supprimée de votre liste d\'amis.';

  @override
  String get friendsAlreadyFriends => 'Déjà amis';

  @override
  String get profileAddFriend => 'Ajouter un ami';

  @override
  String get dailySongTitle => 'Chanson du jour';

  @override
  String get dailySongYourTitle => 'Votre chanson du jour';

  @override
  String get dailySongChoose => 'Choisir votre chanson du jour';

  @override
  String dailySongBy(String artist) {
    return 'par $artist';
  }

  @override
  String get discoverTabPeople => 'Découvrir';

  @override
  String get dailySongNone =>
      'Vous n\'avez pas encore choisi votre chanson du jour';

  @override
  String get dailySongNoneHint =>
      'Partagez avec les autres ce que vous écoutez aujourd\'hui';

  @override
  String get dailySongFriendsTitle => 'Chansons de vos amis';

  @override
  String get dailySongFriendsNone =>
      'Vos amis n\'ont pas encore choisi de chanson du jour';

  @override
  String get dailySongNoFriends =>
      'Ajoutez des amis pour voir leurs chansons du jour';

  @override
  String get onboardingDiscoverTitle => 'Découvrez des personnes';

  @override
  String get onboardingDiscoverDesc =>
      'MusiLink vous connecte avec des personnes qui partagent vos goûts musicaux. Découvrez votre compatibilité selon vos artistes préférés.';

  @override
  String get onboardingProfileTitle => 'Construisez votre profil musical';

  @override
  String get onboardingProfileDesc =>
      'Ajoutez les artistes que vous écoutez le plus. Plus vous en ajoutez, meilleures sont vos correspondances et plus vous découvrez de personnes.';

  @override
  String get onboardingConnectTitle => 'Chattez, partagez, connectez';

  @override
  String get onboardingConnectDesc =>
      'Connectez-vous avec des amis, parlez de musique et partagez votre chanson du jour.';

  @override
  String get onboardingNext => 'Suivant';

  @override
  String get onboardingGetStarted => 'C\'est parti !';

  @override
  String get onboardingSkip => 'Passer';

  @override
  String get photoSetupTitle => 'Ajouter une photo de profil';

  @override
  String get photoSetupSubtitle =>
      'Montrez qui vous êtes. Vous pourrez la modifier à tout moment.';

  @override
  String get photoSetupChoose => 'Choisir une photo';

  @override
  String get photoSetupChange => 'Changer la photo';

  @override
  String get photoSetupContinue => 'Continuer';

  @override
  String get photoSetupSkip => 'Passer pour l\'instant';

  @override
  String get photoSetupUploading => 'Téléchargement...';

  @override
  String get photoSetupGallery => 'Galerie';

  @override
  String get photoSetupCamera => 'Appareil photo';

  @override
  String get photoSetupError =>
      'Impossible de télécharger la photo. Veuillez réessayer.';

  @override
  String get blockUserBlock => 'Bloquer l\'utilisateur';

  @override
  String get blockUserUnblock => 'Débloquer';

  @override
  String blockUserBlockConfirmTitle(String name) {
    return 'Bloquer $name ?';
  }

  @override
  String get blockUserBlockConfirmBody =>
      'Cette personne sera retirée de votre liste d\'amis et n\'apparaîtra plus dans vos découvertes.';

  @override
  String get blockUserBlockConfirm => 'Bloquer';

  @override
  String blockUserBlockedSnackbar(String name) {
    return '$name a été bloqué';
  }

  @override
  String blockUserUnblockedSnackbar(String name) {
    return '$name a été débloqué';
  }

  @override
  String get settingsPrivacy => 'Confidentialité';

  @override
  String get settingsBlockedUsers => 'Utilisateurs bloqués';

  @override
  String get blockedUsersTitle => 'Utilisateurs bloqués';

  @override
  String get blockedUsersEmpty => 'Vous n\'avez bloqué aucun utilisateur';

  @override
  String get genericError => 'Une erreur s\'est produite. Veuillez réessayer.';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsVibration => 'Vibration';

  @override
  String get settingsSound => 'Son';

  @override
  String get settingsLegal => 'Informations légales';

  @override
  String get settingsPrivacyPolicy => 'Politique de confidentialité';

  @override
  String get settingsDeleteAccount => 'Supprimer le compte';

  @override
  String get deleteAccountBody =>
      'Cette action supprimera définitivement votre compte, vos messages, vos réactions, votre photo, vos données musicales et vos informations de profil. Cette action est irréversible.';

  @override
  String get deleteAccountConfirm => 'Supprimer';

  @override
  String get deletingAccount => 'Suppression du compte...';

  @override
  String get reauthTitle => 'Confirmez votre identité';

  @override
  String get reauthBody =>
      'Pour supprimer votre compte, saisissez à nouveau votre mot de passe.';

  @override
  String get reauthConfirm => 'Confirmer';

  @override
  String get reauthWrongAccount =>
      'Le compte sélectionné n\'est pas lié à cette application. Veuillez choisir le bon compte.';

  @override
  String get privacyTitle => 'Politique de confidentialité';

  @override
  String get privacyLastUpdated => 'Dernière mise à jour : 5 mai 2026';

  @override
  String get privacyS1Title => '1. Responsable du traitement';

  @override
  String get privacyS1Body =>
      'MusiLink est développée et exploitée par Pablo Armas (armasp80@gmail.com), établi en Espagne. Pablo Armas agit en tant que responsable du traitement de vos données personnelles conformément au Règlement (UE) 2016/679 (RGPD).';

  @override
  String get privacyS2Title => '2. Données collectées';

  @override
  String get privacyS2Body =>
      'Nous collectons et traitons les données personnelles suivantes :\n\n• Données de compte : nom, adresse e-mail, photo de profil et identifiants de connexion (via e-mail/mot de passe ou Google).\n\n• Données de profil musical : artistes favoris que vous sélectionnez, genres principaux déduits, chanson du jour et chansons partagées.\n\n• Données sociales : messages, demandes d\'amitié et réactions emoji.\n\n• Données techniques : rapports de plantage collectés par Firebase Crashlytics et événements d\'utilisation collectés par Firebase Analytics.';

  @override
  String get privacyS3Title => '3. Utilisation de vos données';

  @override
  String get privacyS3Body =>
      'Vos données sont traitées aux fins suivantes :\n\n• Fourniture du service (compte, compatibilité musicale, découverte, chat). Base légale : exécution d\'un contrat (art. 6.1.b RGPD).\n\n• Fonctionnalités de profil musical : affichage et comparaison des goûts musicaux que vous avez sélectionnés. Base légale : exécution d\'un contrat (art. 6.1.b RGPD).\n\n• Stabilité de l\'application : diagnostic des erreurs et plantages. Base légale : intérêt légitime (art. 6.1.f RGPD).\n\n• Amélioration de l\'application : comprendre l\'utilisation de l\'application pour l\'améliorer. Base légale : intérêt légitime (art. 6.1.f RGPD).';

  @override
  String get privacyS4Title => '4. Services tiers';

  @override
  String get privacyS4Body =>
      'Nous utilisons les services tiers suivants, soumis à leurs propres politiques de confidentialité :\n\n• Google Firebase Firestore, Crashlytics et Analytics — Google LLC. Vos données de profil, messages et événements d\'utilisation sont stockés sur des serveurs situés dans la région européenne (europe-southwest1).\n\n• Google Firebase Storage — Google LLC. Les photos de profil sont stockées sur des serveurs situés aux États-Unis dans le cadre de clauses contractuelles types (Art. 46 RGPD).\n\n• Cloud Functions — Google LLC. Vos données de messages et demandes d\'amitié sont traitées sur des serveurs situés dans la région européenne (europe-southwest1).\n\n• Spotify et Last.fm. Utilisés comme fournisseurs de catalogue musical pour la recherche d\'artistes/chansons et les suggestions d\'artistes. Aucune connexion à un compte Spotify n\'est requise.';

  @override
  String get privacyS5Title => '5. Conservation et suppression des données';

  @override
  String get privacyS5Body =>
      'Nous ne conservons pas vos données au-delà de la durée d\'utilisation de l\'application. Lorsque vous supprimez votre compte via le bouton « Supprimer le compte » dans les Paramètres, nous supprimons vos données privées, photo de profil, relations, demandes, jetons, préférences et données musicales. Le profil public est remplacé par un marqueur anonyme afin de ne pas rompre les références techniques. Les messages que vous avez envoyés sont retirés des conversations et vos réactions sont supprimées ; si une conversation devient vide, elle est supprimée. Certains journaux techniques, rapports de plantage ou données statistiques conservés par Google peuvent être soumis aux propres politiques de conservation de Google.';

  @override
  String get privacyS6Title => '6. Vos droits';

  @override
  String get privacyS6Body =>
      'En vertu du RGPD, vous disposez des droits suivants :\n\n• Accès : demander une copie des données que nous détenons à votre sujet.\n• Rectification : corriger des données inexactes ou incomplètes.\n• Effacement : supprimer votre compte et toutes les données associées via le bouton « Supprimer le compte » dans les Paramètres.\n• Limitation : demander que nous limitions le traitement de vos données.\n• Portabilité : recevoir vos données dans un format structuré et lisible par machine.\n• Opposition : vous opposer au traitement fondé sur l\'intérêt légitime.\n\nPour exercer ces droits, contactez armasp80@gmail.com. Vous pouvez également introduire une réclamation auprès de l\'Agence Espagnole de Protection des Données (AEPD) à l\'adresse www.aepd.es.';

  @override
  String get privacyS7Title => '7. Âge minimum';

  @override
  String get privacyS7Body =>
      'MusiLink est destinée aux utilisateurs âgés de 16 ans et plus. Nous ne collectons pas sciemment de données personnelles auprès de personnes de moins de 16 ans. Si vous pensez qu\'un mineur nous a fourni des données personnelles, contactez-nous à armasp80@gmail.com et nous les supprimerons immédiatement.';

  @override
  String get privacyS8Title => '8. Sécurité';

  @override
  String get privacyS8Body =>
      'Nous mettons en œuvre des mesures techniques et organisationnelles appropriées pour protéger vos données personnelles contre tout accès non autorisé, perte ou altération. Les données sont stockées sur Google Firebase, qui applique des contrôles de sécurité conformes aux normes du secteur.';

  @override
  String get privacyS9Title => '9. Contact';

  @override
  String get privacyS9Body =>
      'Pour toute question concernant cette Politique de Confidentialité ou le traitement de vos données personnelles, contactez-nous à :\n\nPablo Armas\narmasp80@gmail.com';

  @override
  String get privacyS10Title => '10. Transferts internationaux de données';

  @override
  String get privacyS10Body =>
      'Les photos de profil sont stockées dans Google Firebase Storage avec des serveurs situés aux États-Unis. En utilisant l\'application, vous autorisez explicitement ce transfert international de données d\'images. Google a mis en place les mesures techniques et organisationnelles nécessaires en vertu des Clauses Contractuelles Types approuvées par la Commission Européenne (Art. 46 RGPD) pour garantir un niveau de protection adéquat équivalent à celui de l\'UE.\n\nVos données personnelles, messages et données de profil musical sont stockés sur des serveurs situés dans la région européenne (europe-southwest1), au sein de l\'UE.';

  @override
  String get updateRequiredTitle => 'Mise à jour requise';

  @override
  String get updateRequiredBody =>
      'Une nouvelle version de MusiLink est nécessaire pour continuer. Mettez l\'application à jour afin de sécuriser votre compte et vos discussions.';

  @override
  String updateCurrentVersion(String version, int build) {
    return 'Version installée : $version ($build)';
  }

  @override
  String get updateNowButton => 'Mettre à jour';

  @override
  String get updateRetryButton => 'Vérifier à nouveau';

  @override
  String get updateStoreOpenError =>
      'Impossible d\'ouvrir la boutique. Vérifiez votre connexion et réessayez.';
}
