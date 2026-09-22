// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Modern Greek (`el`).
class AppLocalizationsEl extends AppLocalizations {
  AppLocalizationsEl([String locale = 'el']) : super(locale);

  @override
  String get authTagline =>
      'Συνδέσου με ανθρώπους που μοιράζονται τα μουσικά σου γούστα';

  @override
  String get authName => 'Όνομα';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Κωδικός';

  @override
  String get authEnterName => 'Εισάγετε το όνομά σας';

  @override
  String get authEnterEmail => 'Εισάγετε το email σας';

  @override
  String get authInvalidEmail => 'Μη έγκυρο email';

  @override
  String get authEnterPassword => 'Εισάγετε τον κωδικό σας';

  @override
  String get authMinChars => 'Τουλάχιστον 6 χαρακτήρες';

  @override
  String get authErrorEmailInUse => 'Αυτό το email είναι ήδη καταχωρημένο.';

  @override
  String get authErrorInvalidEmail => 'Μη έγκυρο email.';

  @override
  String get authErrorWeakPassword =>
      'Ο κωδικός πρέπει να έχει τουλάχιστον 6 χαρακτήρες.';

  @override
  String get authErrorUserNotFound =>
      'Δεν βρέθηκε λογαριασμός με αυτό το email.';

  @override
  String get authErrorWrongPassword => 'Λανθασμένος κωδικός.';

  @override
  String get authErrorInvalidCredential => 'Μη έγκυρα διαπιστευτήρια.';

  @override
  String get authErrorTooManyRequests => 'Πολλές προσπάθειες. Περιμένετε λίγο.';

  @override
  String authErrorGeneric(String code) {
    return 'Σφάλμα ταυτοποίησης ($code).';
  }

  @override
  String get authSignIn => 'Σύνδεση';

  @override
  String get authCreateAccount => 'Δημιουργία λογαριασμού';

  @override
  String get authOr => 'ή';

  @override
  String get authContinueGoogle => 'Συνέχεια με Google';

  @override
  String get authNoAccount => 'Δεν έχετε λογαριασμό;';

  @override
  String get authHaveAccount => 'Έχετε ήδη λογαριασμό;';

  @override
  String get authRegister => 'Εγγραφή';

  @override
  String get authLogin => 'Σύνδεση';

  @override
  String get authForgotPassword => 'Ξεχάσατε τον κωδικό σας;';

  @override
  String get authPasswordResetSent =>
      'Εάν αυτό το email έχει λογαριασμό με κωδικό, σας στείλαμε έναν σύνδεσμο επαναφοράς.';

  @override
  String get authErrorCouldNotAuth => 'Αδύνατη η ταυτοποίηση. Δοκιμάστε ξανά.';

  @override
  String get authErrorUnexpected => 'Απροσδόκητο σφάλμα. Δοκιμάστε ξανά.';

  @override
  String get authErrorGoogleSignInGeneric => 'Σφάλμα σύνδεσης με Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'Αυτό το email είναι ήδη καταχωρημένο με κωδικό. Συνδεθείτε με email και κωδικό.';

  @override
  String get authPrivacyLink => 'Πολιτική Απορρήτου';

  @override
  String get termsAcceptanceTitle => 'Όροι και Προϋποθέσεις';

  @override
  String get termsAcceptanceIntro =>
      'Για να συνεχίσετε να χρησιμοποιείτε το MusiLink, διαβάστε και αποδεχτείτε τους όρους.';

  @override
  String termsAcceptanceVersion(String version) {
    return 'Έκδοση $version';
  }

  @override
  String get termsOpenDocument => 'Διαβάστε τους Όρους και Προϋποθέσεις';

  @override
  String get termsAcceptCheckbox =>
      'Έχω διαβάσει και αποδέχομαι τους Όρους και Προϋποθέσεις του MusiLink.';

  @override
  String get termsAcceptAndContinue => 'Αποδοχή και συνέχεια';

  @override
  String get termsAccepting => 'Αποδοχή…';

  @override
  String get termsSaveError =>
      'Δεν ήταν δυνατή η αποθήκευση της αποδοχής σας. Δοκιμάστε ξανά.';

  @override
  String get termsOpenError => 'Δεν ήταν δυνατό το άνοιγμα του συνδέσμου.';

  @override
  String get authUsername => 'Όνομα χρήστη';

  @override
  String get authUsernameHint => 'πεζά γράμματα, αριθμοί και _';

  @override
  String get authUsernameTooShort => 'Τουλάχιστον 3 χαρακτήρες';

  @override
  String get authUsernameTooLong => 'Μέγιστο 20 χαρακτήρες';

  @override
  String get authUsernameInvalidChars => 'Μόνο γράμματα, αριθμοί και _';

  @override
  String get authUsernameTaken => 'Αυτό το όνομα χρήστη χρησιμοποιείται ήδη';

  @override
  String get authUsernameAvailable => 'Διαθέσιμο';

  @override
  String get authUsernameChecking => 'Έλεγχος...';

  @override
  String get usernameSetupTitle => 'Επιλέξτε το όνομα χρήστη σας';

  @override
  String get usernameSetupSubtitle =>
      'Έτσι θα σας βρίσκουν άλλοι στο MusiLink.';

  @override
  String get usernameSetupButton => 'Συνέχεια';

  @override
  String get discoverErrorLoading => 'Σφάλμα φόρτωσης ανακάλυψης';

  @override
  String get discoverNoUsers => 'Δεν υπάρχουν χρήστες με μουσικά δεδομένα';

  @override
  String get discoverNoUsersHint =>
      'Καθώς περισσότεροι χρήστες δημιουργούν το μουσικό τους προφίλ, θα εμφανίζονται εδώ';

  @override
  String get navDiscover => 'Ανακάλυψη';

  @override
  String get navStats => 'Το Top μου';

  @override
  String get navMessages => 'Μηνύματα';

  @override
  String get navFriends => 'Φίλοι';

  @override
  String get searchTitle => 'Αναζήτηση χρηστών';

  @override
  String get searchHint => 'Όνομα χρήστη...';

  @override
  String get searchNoResults => 'Δεν βρέθηκαν χρήστες';

  @override
  String get searchTypeToSearch => 'Πληκτρολογήστε ένα όνομα για αναζήτηση';

  @override
  String get profileTitle => 'Μουσικό προφίλ';

  @override
  String get profileStartChat => 'Συνομιλία';

  @override
  String get profileNoData => 'Αυτός ο χρήστης δεν έχει ακόμη μουσικά δεδομένα';

  @override
  String get profileTopArtists => 'Κορυφαίοι Καλλιτέχνες';

  @override
  String get profileTopGenres => 'Κορυφαία Είδη';

  @override
  String get profileCompatible => 'συμβατοί';

  @override
  String get profileSharedArtists => 'Κοινοί καλλιτέχνες';

  @override
  String get profileSharedGenres => 'Κοινά είδη';

  @override
  String get chatWriteMessage => 'Γράψτε ένα μήνυμα...';

  @override
  String get chatSearchSong => 'Αναζήτηση τραγουδιού...';

  @override
  String get chatShareSong => 'Κοινοποίηση τραγουδιού';

  @override
  String get chatDeletedUser =>
      'Αυτός ο λογαριασμός έχει διαγραφεί. Δεν μπορείτε πλέον να στέλνετε μηνύματα.';

  @override
  String get chatBlockedCannotSend =>
      'Μπορείτε να δείτε το ιστορικό, αλλά δεν μπορείτε να στείλετε μηνύματα σε αυτήν τη συνομιλία.';

  @override
  String get chatNotFriendsCannotSend =>
      'Μπορείτε να δείτε το ιστορικό, αλλά μόνο φίλοι μπορούν να στέλνουν μηνύματα σε αυτήν τη συνομιλία.';

  @override
  String get chatSendFirst => 'Στείλτε το πρώτο μήνυμα';

  @override
  String get chatTypeToSearch => 'Πληκτρολογήστε για αναζήτηση τραγουδιών';

  @override
  String get chatNoResults => 'Δεν βρέθηκαν αποτελέσματα';

  @override
  String get chatDeleteTitle => 'Διαγραφή συνομιλίας';

  @override
  String get chatDeleteConfirm => 'Διαγραφή';

  @override
  String get chatDeleteCancel => 'Άκυρο';

  @override
  String get chatDateToday => 'Σήμερα';

  @override
  String get chatDateYesterday => 'Χθες';

  @override
  String get statsArtists => 'Καλλιτέχνες';

  @override
  String get statsGenres => 'Είδη';

  @override
  String get statsEditArtists => 'Επεξεργασία καλλιτεχνών';

  @override
  String get statsNoData => 'Δεν υπάρχουν διαθέσιμα δεδομένα';

  @override
  String get socialNow => 'Τώρα';

  @override
  String socialMinutes(int minutes) {
    return '$minutes λεπτ.';
  }

  @override
  String socialDays(int days) {
    return '$daysμ';
  }

  @override
  String get socialNoChats => 'Δεν υπάρχουν συνομιλίες ακόμη';

  @override
  String get socialNoChatsHint =>
      'Αναζητήστε χρήστες για να ξεκινήσετε συνομιλία';

  @override
  String get socialErrorLoading => 'Σφάλμα φόρτωσης συνομιλιών';

  @override
  String get socialUser => 'Χρήστης';

  @override
  String get artistSelectorTitle => 'Οι Κορυφαίοι Καλλιτέχνες μου';

  @override
  String artistSelectorSubtitle(int count, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count από $max καλλιτέχνες επιλέχθηκαν · σύρετε για κατάταξη',
      one: '1 από $max καλλιτέχνες επιλέχθηκε · σύρετε για κατάταξη',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorSearchHint => 'Αναζήτηση καλλιτεχνών...';

  @override
  String get artistSelectorContinue => 'Συνέχεια';

  @override
  String artistSelectorContinueLocked(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Προσθέστε $remaining ακόμα καλλιτέχνες',
      one: 'Προσθέστε 1 ακόμα καλλιτέχνη',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorNoResults => 'Δεν βρέθηκαν καλλιτέχνες';

  @override
  String get artistSelectorEmpty =>
      'Αναζητήστε τους αγαπημένους σας καλλιτέχνες για να ξεκινήσετε';

  @override
  String get artistSelectorSuggested => 'Προτεινόμενοι';

  @override
  String get artistSelectorStageBasic => 'Βασικό';

  @override
  String get artistSelectorStageGood => 'Καλό';

  @override
  String get artistSelectorStageGreat => 'Εξαιρετικό';

  @override
  String get artistSelectorStageExpert => 'Ειδικός';

  @override
  String get menuAccountOptions => 'Επιλογές λογαριασμού';

  @override
  String get menuSignOut => 'Αποσύνδεση';

  @override
  String get signingOut => 'Αποσύνδεση...';

  @override
  String get friendsReceivedRequests => 'Ληφθείσες αιτήσεις';

  @override
  String get friendsSentRequests => 'Απεσταλμένες αιτήσεις';

  @override
  String get friendsMyFriends => 'Οι φίλοι μου';

  @override
  String get friendsAccept => 'Αποδοχή';

  @override
  String get friendsReject => 'Απόρριψη';

  @override
  String get friendsCancel => 'Ακύρωση';

  @override
  String get friendsSendRequest => 'Αποστολή αιτήματος';

  @override
  String get friendsRequestSent => 'Αίτημα εστάλη';

  @override
  String get friendsNoRequests => 'Δεν υπάρχουν εκκρεμή αιτήματα';

  @override
  String get friendsNoFriends => 'Δεν έχετε ακόμη φίλους';

  @override
  String get friendsNoFriendsHint =>
      'Αναζητήστε χρήστες για να προσθέσετε φίλους';

  @override
  String get friendsRemove => 'Αφαίρεση φίλου';

  @override
  String get friendsRemoveBody =>
      'Αυτό το άτομο θα αφαιρεθεί από τη λίστα φίλων σας.';

  @override
  String get profileAddFriend => 'Προσθήκη φίλου';

  @override
  String get dailySongTitle => 'Τραγούδι της ημέρας';

  @override
  String get dailySongYourTitle => 'Το τραγούδι σας της ημέρας';

  @override
  String get dailySongChoose => 'Επιλέξτε το τραγούδι σας της ημέρας';

  @override
  String get discoverTabPeople => 'Ανακαλύψτε ανθρώπους';

  @override
  String get dailySongNone => 'Δεν έχετε επιλέξει ακόμη τραγούδι της ημέρας';

  @override
  String get dailySongNoneHint => 'Μοιραστείτε με τους άλλους τι ακούτε σήμερα';

  @override
  String get dailySongFriendsTitle => 'Τα τραγούδια των φίλων σας';

  @override
  String get dailySongFriendsNone =>
      'Οι φίλοι σας δεν έχουν επιλέξει ακόμη τραγούδι της ημέρας';

  @override
  String get dailySongNoFriends =>
      'Προσθέστε φίλους για να δείτε το τραγούδι τους της ημέρας';

  @override
  String get dailySongSaveError =>
      'Δεν ήταν δυνατή η δημοσίευση του τραγουδιού. Ελέγξτε τη σύνδεσή σας και δοκιμάστε ξανά.';

  @override
  String get dailySongRefreshError =>
      'Δεν ήταν δυνατή η ανανέωση από τον διακομιστή. Εμφανίζονται τα προηγούμενα δεδομένα.';

  @override
  String get dailySongLoadError =>
      'Δεν ήταν δυνατή η φόρτωση των τραγουδιών της ημέρας.';

  @override
  String get dailySongRetry => 'Δοκιμάστε ξανά';

  @override
  String get onboardingDiscoverTitle => 'Ανακαλύψτε ανθρώπους';

  @override
  String get onboardingDiscoverDesc =>
      'Το MusiLink σας συνδέει με ανθρώπους που μοιράζονται τα μουσικά σας γούστα. Δείτε πόσο συμβατοί είστε βάσει των αγαπημένων σας καλλιτεχνών.';

  @override
  String get onboardingProfileTitle => 'Δημιουργήστε το μουσικό σας προφίλ';

  @override
  String get onboardingProfileDesc =>
      'Προσθέστε τους καλλιτέχνες που αγαπάτε περισσότερο. Όσο περισσότερους προσθέτετε, τόσο καλύτερες οι αντιστοιχίσεις — και τόσο περισσότεροι άνθρωποι θα ανακαλύψετε.';

  @override
  String get onboardingConnectTitle => 'Συνομιλήστε, μοιραστείτε, συνδεθείτε';

  @override
  String get onboardingConnectDesc =>
      'Συνδεθείτε με φίλους, μιλήστε για μουσική και μοιραστείτε το τραγούδι σας της ημέρας.';

  @override
  String get onboardingNext => 'Επόμενο';

  @override
  String get onboardingGetStarted => 'Ας ξεκινήσουμε';

  @override
  String get onboardingSkip => 'Παράλειψη';

  @override
  String get photoSetupTitle => 'Προσθέστε φωτογραφία προφίλ';

  @override
  String get photoSetupSubtitle =>
      'Ενημερώστε τους άλλους για το ποιος είστε. Μπορείτε να το αλλάξετε αργότερα.';

  @override
  String get photoSetupChoose => 'Επιλογή φωτογραφίας';

  @override
  String get photoSetupChange => 'Αλλαγή φωτογραφίας';

  @override
  String get photoSetupContinue => 'Συνέχεια';

  @override
  String get photoSetupSkip => 'Παράλειψη προς το παρόν';

  @override
  String get photoSetupGallery => 'Γκαλερί';

  @override
  String get photoSetupCamera => 'Κάμερα';

  @override
  String get photoSetupError =>
      'Δεν ήταν δυνατή η μεταφόρτωση φωτογραφίας. Δοκιμάστε ξανά.';

  @override
  String get blockUserBlock => 'Αποκλεισμός χρήστη';

  @override
  String get blockUserUnblock => 'Άρση αποκλεισμού';

  @override
  String blockUserBlockConfirmTitle(String name) {
    return 'Αποκλεισμός $name;';
  }

  @override
  String get blockUserBlockConfirmBody =>
      'Θα αφαιρεθεί από τη λίστα φίλων σου και δεν θα εμφανίζεται στις ανακαλύψεις σου.';

  @override
  String get blockUserBlockConfirm => 'Αποκλεισμός';

  @override
  String blockUserBlockedSnackbar(String name) {
    return 'Ο $name αποκλείστηκε';
  }

  @override
  String blockUserUnblockedSnackbar(String name) {
    return 'Ο αποκλεισμός του $name αφαιρέθηκε';
  }

  @override
  String get reportProfileAction => 'Αναφορά προφίλ';

  @override
  String get reportMessageAction => 'Αναφορά μηνύματος';

  @override
  String reportProfileTitle(String name) {
    return 'Αναφορά του χρήστη $name';
  }

  @override
  String get reportMessageTitle => 'Αναφορά μηνύματος';

  @override
  String get reportReasonPrompt => 'Επιλέξτε τον λόγο της αναφοράς:';

  @override
  String get reportReasonSpam => 'Ανεπιθύμητο ή παραπλανητικό περιεχόμενο';

  @override
  String get reportReasonHarassment => 'Παρενόχληση ή απειλές';

  @override
  String get reportReasonSexualContent => 'Ακατάλληλο σεξουαλικό περιεχόμενο';

  @override
  String get reportReasonHateSpeech => 'Μίσος ή διακρίσεις';

  @override
  String get reportReasonImpersonation => 'Πλαστοπροσωπία';

  @override
  String get reportReasonOther => 'Άλλος λόγος';

  @override
  String get reportSubmitted =>
      'Η αναφορά στάλθηκε. Θα την εξετάσουμε το συντομότερο δυνατό.';

  @override
  String get reportAlreadySubmitted =>
      'Έχετε ήδη αναφέρει αυτό το περιεχόμενο.';

  @override
  String get reportSubmitError =>
      'Δεν ήταν δυνατή η αποστολή της αναφοράς. Δοκιμάστε ξανά.';

  @override
  String get settingsPrivacy => 'Απόρρητο';

  @override
  String get settingsBlockedUsers => 'Αποκλεισμένοι χρήστες';

  @override
  String get blockedUsersTitle => 'Αποκλεισμένοι χρήστες';

  @override
  String get blockedUsersEmpty => 'Δεν έχεις αποκλείσει κανέναν χρήστη';

  @override
  String get genericError => 'Κάτι πήγε στραβά. Δοκιμάστε ξανά.';

  @override
  String get settingsTitle => 'Ρυθμίσεις';

  @override
  String get settingsAppearance => 'Εμφάνιση';

  @override
  String get settingsTheme => 'Θέμα';

  @override
  String get themeSystem => 'Σύστημα';

  @override
  String get themeLight => 'Φωτεινό';

  @override
  String get themeDark => 'Σκοτεινό';

  @override
  String get settingsNotifications => 'Ειδοποιήσεις';

  @override
  String get settingsVibration => 'Δόνηση';

  @override
  String get settingsSound => 'Ήχος';

  @override
  String get pushNotificationsTitle => 'Μην χάσετε κανένα μήνυμα';

  @override
  String get pushNotificationsBody =>
      'Ενεργοποιήστε τις ειδοποιήσεις για να λαμβάνετε μηνύματα και αιτήματα φιλίας ακόμη και όταν το MusiLink είναι κλειστό.';

  @override
  String get pushNotificationsEnable => 'Ενεργοποίηση ειδοποιήσεων';

  @override
  String get pushNotificationsInstallBody =>
      'Στο iPhone, ανοίξτε το MusiLink στο Safari, πατήστε Κοινή χρήση, έπειτα «Περισσότερα» και επιλέξτε «Προσθήκη στην οθόνη Αφετηρίας». Έπειτα ανοίξτε την εφαρμογή από το εικονίδιό της.';

  @override
  String get pushNotificationsBlockedBody =>
      'Οι ειδοποιήσεις είναι αποκλεισμένες. Μπορείτε να τις ενεργοποιήσετε στις Ρυθμίσεις iPhone → Ειδοποιήσεις → MusiLink.';

  @override
  String get pushNotificationsUnsupportedBody =>
      'Αυτό το πρόγραμμα περιήγησης ή η συσκευή δεν υποστηρίζει ειδοποιήσεις web.';

  @override
  String get pushNotificationsError =>
      'Δεν ήταν δυνατή η ενεργοποίηση των ειδοποιήσεων. Δοκιμάστε ξανά.';

  @override
  String get pwaInstallTitle => 'Εγκαταστήστε το MusiLink στο iPhone σας';

  @override
  String get pwaInstallBody =>
      'Για να λαμβάνετε ειδοποιήσεις και να απολαμβάνετε την πλήρη εμπειρία:';

  @override
  String get pwaInstallStepMore => 'Πατήστε Περισσότερα (···), κάτω δεξιά.';

  @override
  String get pwaInstallStepShare => 'Πατήστε Κοινή χρήση.';

  @override
  String get pwaInstallStepSeeMore => 'Πατήστε «Περισσότερα».';

  @override
  String get pwaInstallStepAdd => 'Επιλέξτε «Προσθήκη στην οθόνη Αφετηρίας».';

  @override
  String get pwaInstallStepOpen =>
      'Ανοίξτε το MusiLink από το νέο εικονίδιό του.';

  @override
  String get pwaInstallContinue => 'Συνέχεια στο Safari';

  @override
  String get settingsLegal => 'Νομικά';

  @override
  String get settingsPrivacyPolicy => 'Πολιτική απορρήτου';

  @override
  String get settingsDeleteAccount => 'Διαγραφή λογαριασμού';

  @override
  String get deleteAccountBody =>
      'Αυτό θα διαγράψει μόνιμα τον λογαριασμό σας, τα μηνύματά σας, τις αντιδράσεις σας, τη φωτογραφία σας, τα μουσικά σας δεδομένα και τις πληροφορίες προφίλ σας. Αυτή η ενέργεια δεν μπορεί να αναιρεθεί.';

  @override
  String get deleteAccountConfirm => 'Διαγραφή';

  @override
  String get deletingAccount => 'Έναρξη διαγραφής λογαριασμού...';

  @override
  String get accountDeletionRequested =>
      'Η διαγραφή του λογαριασμού σας ξεκίνησε. Μπορείτε να κλείσετε την εφαρμογή· η διαδικασία θα συνεχιστεί στο παρασκήνιο.';

  @override
  String get accountDeletionPending =>
      'Αυτός ο λογαριασμός διαγράφεται αυτήν τη στιγμή. Δοκιμάστε ξανά αργότερα.';

  @override
  String get reauthTitle => 'Επιβεβαιώστε την ταυτότητά σας';

  @override
  String get reauthBody =>
      'Για να διαγράψετε τον λογαριασμό σας, εισάγετε ξανά τον κωδικό σας.';

  @override
  String get reauthConfirm => 'Επιβεβαίωση';

  @override
  String get reauthWrongAccount =>
      'Ο επιλεγμένος λογαριασμός δεν είναι συνδεδεμένος με αυτή την εφαρμογή. Επιλέξτε τον σωστό λογαριασμό.';

  @override
  String get updateRequiredTitle => 'Απαιτείται ενημέρωση';

  @override
  String get updateRequiredBody =>
      'Απαιτείται μια νέα έκδοση του MusiLink για να συνεχίσετε. Ενημερώστε τώρα την εφαρμογή για ασφαλή λειτουργία του λογαριασμού και των συνομιλιών σας.';

  @override
  String updateCurrentVersion(String version, int build) {
    return 'Εγκατεστημένη έκδοση: $version ($build)';
  }

  @override
  String get updateNowButton => 'Ενημέρωση τώρα';

  @override
  String get updateRetryButton => 'Νέος έλεγχος';

  @override
  String get updateStoreOpenError =>
      'Δεν ήταν δυνατό το άνοιγμα του καταστήματος. Ελέγξτε τη σύνδεσή σας και δοκιμάστε ξανά.';
}
