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
  String get authErrorGoogleSignIn => 'Δεν ήταν δυνατή η σύνδεση με Google.';

  @override
  String get authErrorGoogleSignInGeneric => 'Σφάλμα σύνδεσης με Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'Αυτό το email είναι ήδη καταχωρημένο με κωδικό. Συνδεθείτε με email και κωδικό.';

  @override
  String get authUsername => 'Όνομα χρήστη';

  @override
  String get authEnterUsername => 'Επιλέξτε όνομα χρήστη';

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
  String get discoverTitle => 'Ανακαλύψτε ανθρώπους';

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
  String get chatSendFirst => 'Στείλτε το πρώτο μήνυμα';

  @override
  String get chatTypeToSearch => 'Πληκτρολογήστε για αναζήτηση τραγουδιών';

  @override
  String get chatNoResults => 'Δεν βρέθηκαν αποτελέσματα';

  @override
  String get chatDeleteTitle => 'Διαγραφή συνομιλίας';

  @override
  String get chatDeleteBody => 'Αυτή η συνομιλία θα διαγραφεί.';

  @override
  String get chatDeleteConfirm => 'Διαγραφή';

  @override
  String get chatDeleteCancel => 'Άκυρο';

  @override
  String get statsTracks => 'Τραγούδια';

  @override
  String get statsArtists => 'Καλλιτέχνες';

  @override
  String get statsGenres => 'Είδη';

  @override
  String get statsShortTerm => '4 εβδομάδες';

  @override
  String get statsMediumTerm => '6 μήνες';

  @override
  String get statsLongTerm => '1 χρόνος';

  @override
  String statsError(String error) {
    return 'Σφάλμα: $error';
  }

  @override
  String get statsEditArtists => 'Επεξεργασία καλλιτεχνών';

  @override
  String get statsNoData => 'Δεν υπάρχουν διαθέσιμα δεδομένα';

  @override
  String get statsOfflineCache =>
      'Εκτός σύνδεσης — εμφάνιση αποθηκευμένων δεδομένων';

  @override
  String get statsStaleCache => 'Εμφάνιση δεδομένων από πάνω από 48 ώρες πριν';

  @override
  String get statsOfflineNoData =>
      'Δεν υπάρχει σύνδεση και δεν υπάρχουν αποθηκευμένα δεδομένα.\nΕπισκεφθείτε αυτή την καρτέλα online πρώτα.';

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
  String artistSelectorSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count καλλιτέχνες · όσο περισσότερους προσθέτετε, τόσο καλύτερες οι αντιστοιχίσεις',
      one:
          '1 καλλιτέχνης · όσο περισσότερους προσθέτετε, τόσο καλύτερες οι αντιστοιχίσεις',
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
  String get artistSelectorStageHint =>
      'Προσθέστε περισσότερους για να βελτιώσετε τις συστάσεις σας';

  @override
  String get menuProfile => 'Το προφίλ μου';

  @override
  String get menuAccountOptions => 'Επιλογές λογαριασμού';

  @override
  String get menuLightMode => 'Ανοιχτή λειτουργία';

  @override
  String get menuDarkMode => 'Σκοτεινή λειτουργία';

  @override
  String get menuSignOut => 'Αποσύνδεση';

  @override
  String get signingOut => 'Αποσύνδεση...';

  @override
  String discoverySharedArtists(String artists) {
    return 'Κοινοί καλλιτέχνες: $artists';
  }

  @override
  String discoverySharedGenres(String genres) {
    return 'Κοινά είδη: $genres';
  }

  @override
  String discoveryCompatible(String score) {
    return '$score% συμβατοί';
  }

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
  String get friendsAlreadyFriends => 'Ήδη φίλοι';

  @override
  String get profileAddFriend => 'Προσθήκη φίλου';

  @override
  String get dailySongTitle => 'Τραγούδι της ημέρας';

  @override
  String get dailySongYourTitle => 'Το τραγούδι σας της ημέρας';

  @override
  String get dailySongChoose => 'Επιλέξτε το τραγούδι σας της ημέρας';

  @override
  String dailySongBy(String artist) {
    return 'από $artist';
  }

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
  String get photoSetupUploading => 'Μεταφόρτωση...';

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
  String get settingsNotifications => 'Ειδοποιήσεις';

  @override
  String get settingsVibration => 'Δόνηση';

  @override
  String get settingsSound => 'Ήχος';

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
  String get deletingAccount => 'Διαγραφή λογαριασμού...';

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
  String get privacyTitle => 'Πολιτική Απορρήτου';

  @override
  String get privacyLastUpdated => 'Τελευταία ενημέρωση: 5 Μαΐου 2026';

  @override
  String get privacyS1Title => '1. Υπεύθυνος Επεξεργασίας Δεδομένων';

  @override
  String get privacyS1Body =>
      'Το MusiLink αναπτύσσεται και λειτουργεί από τον Pablo Armas (armasp80@gmail.com), εγκατεστημένο στην Ισπανία. Ο Pablo Armas είναι ο υπεύθυνος επεξεργασίας που είναι αρμόδιος για την επεξεργασία των προσωπικών σας δεδομένων σύμφωνα με τον Κανονισμό (ΕΕ) 2016/679 (ΓΚΠΔ).';

  @override
  String get privacyS2Title => '2. Δεδομένα που Συλλέγουμε';

  @override
  String get privacyS2Body =>
      'Συλλέγουμε και επεξεργαζόμαστε τα ακόλουθα προσωπικά δεδομένα:\n\n• Δεδομένα λογαριασμού: όνομα, διεύθυνση email, φωτογραφία προφίλ και αναγνωριστικά σύνδεσης (μέσω email/κωδικού ή Google Sign-In).\n\n• Δεδομένα μουσικού προφίλ: κορυφαίοι καλλιτέχνες που επιλέγετε, συναγόμενα κορυφαία είδη, επιλογές τραγουδιού της ημέρας και κοινοποιημένα τραγούδια.\n\n• Κοινωνικά δεδομένα: μηνύματα, αιτήματα φιλίας και αντιδράσεις emoji.\n\n• Τεχνικά δεδομένα: αναφορές σφαλμάτων που συλλέγονται από το Firebase Crashlytics και γεγονότα χρήσης που συλλέγονται από το Firebase Analytics.';

  @override
  String get privacyS3Title => '3. Πώς Χρησιμοποιούμε τα Δεδομένα σας';

  @override
  String get privacyS3Body =>
      'Τα δεδομένα σας επεξεργάζονται για τους ακόλουθους σκοπούς:\n\n• Παροχή της υπηρεσίας (λογαριασμός, μουσική συμβατότητα, ανακάλυψη, συνομιλία). Νομική βάση: εκτέλεση σύμβασης (Άρθρο 6.1.β ΓΚΠΔ).\n\n• Λειτουργίες μουσικού προφίλ: εμφάνιση και σύγκριση του επιλεγμένου μουσικού σας γούστου. Νομική βάση: εκτέλεση σύμβασης (Άρθρο 6.1.β ΓΚΠΔ).\n\n• Σταθερότητα εφαρμογής: διάγνωση σφαλμάτων. Νομική βάση: έννομο συμφέρον (Άρθρο 6.1.στ ΓΚΠΔ).\n\n• Βελτίωση εφαρμογής: κατανόηση του τρόπου χρήσης της εφαρμογής για τη βελτίωσή της. Νομική βάση: έννομο συμφέρον (Άρθρο 6.1.στ ΓΚΠΔ).';

  @override
  String get privacyS4Title => '4. Υπηρεσίες Τρίτων';

  @override
  String get privacyS4Body =>
      'Χρησιμοποιούμε τις ακόλουθες υπηρεσίες τρίτων, καθεμία με τη δική της πολιτική απορρήτου:\n\n• Google Firebase Firestore, Crashlytics και Analytics — Google LLC. Τα δεδομένα προφίλ, τα μηνύματα και τα γεγονότα χρήσης αποθηκεύονται σε διακομιστές στην ευρωπαϊκή περιοχή (europe-southwest1).\n\n• Google Firebase Storage — Google LLC. Οι φωτογραφίες προφίλ αποθηκεύονται σε διακομιστές που βρίσκονται στις Ηνωμένες Πολιτείες υπό τυποποιημένες συμβατικές ρήτρες (Άρθρο 46 ΓΚΠΔ).\n\n• Cloud Functions — Google LLC. Τα δεδομένα μηνυμάτων και αιτημάτων φιλίας επεξεργάζονται σε διακομιστές στην ευρωπαϊκή περιοχή (europe-southwest1).\n\n• Spotify και Last.fm. Χρησιμοποιούνται ως πάροχοι μουσικού καταλόγου για αναζήτηση καλλιτεχνών/τραγουδιών και προτάσεις. Δεν απαιτείται σύνδεση λογαριασμού Spotify.';

  @override
  String get privacyS5Title => '5. Διατήρηση και Διαγραφή Δεδομένων';

  @override
  String get privacyS5Body =>
      'Δεν διατηρούμε τα δεδομένα σας πέρα από τον χρόνο που χρησιμοποιείτε την εφαρμογή. Όταν διαγράφετε τον λογαριασμό σας μέσω του κουμπιού «Διαγραφή λογαριασμού» στις Ρυθμίσεις, διαγράφουμε τα ιδιωτικά σας δεδομένα, τη φωτογραφία προφίλ, τις σχέσεις, τα αιτήματα, τα tokens, τις προτιμήσεις και τα μουσικά δεδομένα. Το δημόσιο προφίλ αντικαθίσταται από ανώνυμο placeholder. Τα μηνύματα που στείλατε αφαιρούνται από τις συνομιλίες· εάν μια συνομιλία αδειάσει, διαγράφεται. Ορισμένες τεχνικές εγγραφές που διατηρεί η Google μπορεί να υπόκεινται στις δικές της πολιτικές διατήρησης.';

  @override
  String get privacyS6Title => '6. Τα Δικαιώματά σας';

  @override
  String get privacyS6Body =>
      'Δυνάμει του ΓΚΠΔ, έχετε τα ακόλουθα δικαιώματα:\n\n• Πρόσβαση: αίτημα αντιγράφου των δεδομένων που διατηρούμε για εσάς.\n• Διόρθωση: διόρθωση ανακριβών ή ελλιπών δεδομένων.\n• Διαγραφή: διαγραφή του λογαριασμού και όλων των δεδομένων μέσω του κουμπιού «Διαγραφή λογαριασμού» στις Ρυθμίσεις.\n• Περιορισμός: αίτημα περιορισμού της επεξεργασίας των δεδομένων σας.\n• Φορητότητα: λήψη των δεδομένων σας σε δομημένη, αναγνώσιμη από μηχανή μορφή.\n• Εναντίωση: εναντίωση στην επεξεργασία βάσει έννομου συμφέροντος.\n\nΓια να ασκήσετε αυτά τα δικαιώματα, επικοινωνήστε στο armasp80@gmail.com. Μπορείτε επίσης να υποβάλετε καταγγελία στην Αρχή Προστασίας Δεδομένων Προσωπικού Χαρακτήρα (ΑΠΔΠΧ) στο www.dpa.gr.';

  @override
  String get privacyS7Title => '7. Ελάχιστη Ηλικία';

  @override
  String get privacyS7Body =>
      'Το MusiLink απευθύνεται σε χρήστες 16 ετών και άνω. Δεν συλλέγουμε εν γνώσει μας προσωπικά δεδομένα από άτομα κάτω των 16 ετών. Εάν πιστεύετε ότι ανήλικος μάς έχει παράσχει προσωπικά δεδομένα, επικοινωνήστε μαζί μας στο armasp80@gmail.com και θα τα διαγράψουμε αμέσως.';

  @override
  String get privacyS8Title => '8. Ασφάλεια';

  @override
  String get privacyS8Body =>
      'Εφαρμόζουμε κατάλληλα τεχνικά και οργανωτικά μέτρα για την προστασία των προσωπικών σας δεδομένων από μη εξουσιοδοτημένη πρόσβαση, απώλεια ή αλλοίωση. Τα δεδομένα αποθηκεύονται στο Google Firebase, το οποίο εφαρμόζει ελέγχους ασφαλείας βιομηχανικού επιπέδου.';

  @override
  String get privacyS9Title => '9. Επικοινωνία';

  @override
  String get privacyS9Body =>
      'Για οποιαδήποτε ερώτηση σχετικά με αυτή την Πολιτική Απορρήτου ή την επεξεργασία των δεδομένων σας, επικοινωνήστε:\n\nPablo Armas\narmasp80@gmail.com';

  @override
  String get privacyS10Title => '10. Διεθνείς Μεταφορές Δεδομένων';

  @override
  String get privacyS10Body =>
      'Οι φωτογραφίες προφίλ αποθηκεύονται στο Google Firebase Storage με διακομιστές που βρίσκονται στις Ηνωμένες Πολιτείες. Χρησιμοποιώντας την εφαρμογή, εξουσιοδοτείτε ρητά αυτή τη διεθνή μεταφορά δεδομένων εικόνας. Η Google έχει εφαρμόσει τα απαραίτητα τεχνικά και οργανωτικά μέτρα βάσει των Τυποποιημένων Συμβατικών Ρητρών που εγκρίθηκαν από την Ευρωπαϊκή Επιτροπή (Άρθρο 46 ΓΚΠΔ) για την εξασφάλιση επαρκούς επιπέδου προστασίας ισοδύναμου με αυτό στην ΕΕ.\n\nΤα προσωπικά σας δεδομένα, τα μηνύματα και τα δεδομένα μουσικού προφίλ αποθηκεύονται σε διακομιστές στην ευρωπαϊκή περιοχή (europe-southwest1), εντός της ΕΕ.';
}
