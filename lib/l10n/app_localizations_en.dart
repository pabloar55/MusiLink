// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get authTagline => 'Connect with people who share your music taste';

  @override
  String get authName => 'Name';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authEnterName => 'Enter your name';

  @override
  String get authEnterEmail => 'Enter your email';

  @override
  String get authInvalidEmail => 'Invalid email';

  @override
  String get authEnterPassword => 'Enter your password';

  @override
  String get authMinChars => 'Minimum 6 characters';

  @override
  String get authErrorEmailInUse => 'This email is already registered.';

  @override
  String get authErrorInvalidEmail => 'Invalid email.';

  @override
  String get authErrorWeakPassword => 'Password must be at least 6 characters.';

  @override
  String get authErrorUserNotFound => 'No account found with this email.';

  @override
  String get authErrorWrongPassword => 'Incorrect password.';

  @override
  String get authErrorInvalidCredential => 'Invalid credentials.';

  @override
  String get authErrorTooManyRequests =>
      'Too many attempts. Please wait a moment.';

  @override
  String authErrorGeneric(String code) {
    return 'Authentication error ($code).';
  }

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authOr => 'or';

  @override
  String get authContinueGoogle => 'Continue with Google';

  @override
  String get authNoAccount => 'Don\'t have an account?';

  @override
  String get authHaveAccount => 'Already have an account?';

  @override
  String get authRegister => 'Sign up';

  @override
  String get authLogin => 'Log in';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authPasswordResetSent =>
      'If this email has a password account, we sent you a reset link.';

  @override
  String get authErrorCouldNotAuth =>
      'Could not authenticate. Please try again.';

  @override
  String get authErrorUnexpected => 'Unexpected error. Please try again.';

  @override
  String get authErrorGoogleSignIn => 'Could not sign in with Google.';

  @override
  String get authErrorGoogleSignInGeneric => 'Error signing in with Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'This email is already registered with a password. Please sign in with email and password.';

  @override
  String get authUsername => 'Username';

  @override
  String get authEnterUsername => 'Choose a username';

  @override
  String get authUsernameHint => 'lowercase letters, numbers and _';

  @override
  String get authUsernameTooShort => 'At least 3 characters';

  @override
  String get authUsernameTooLong => 'Max 20 characters';

  @override
  String get authUsernameInvalidChars => 'Only letters, numbers and _';

  @override
  String get authUsernameTaken => 'This username is already taken';

  @override
  String get authUsernameAvailable => 'Available';

  @override
  String get authUsernameChecking => 'Checking...';

  @override
  String get usernameSetupTitle => 'Choose your username';

  @override
  String get usernameSetupSubtitle =>
      'This is how others will find you on MusiLink.';

  @override
  String get usernameSetupButton => 'Continue';

  @override
  String get discoverTitle => 'Discover people';

  @override
  String get discoverErrorLoading => 'Error loading discovery';

  @override
  String get discoverNoUsers => 'No users with music data';

  @override
  String get discoverNoUsersHint =>
      'As more users create their music profile, they will appear here';

  @override
  String get navDiscover => 'Discover';

  @override
  String get navStats => 'My Top';

  @override
  String get navMessages => 'Messages';

  @override
  String get navFriends => 'Friends';

  @override
  String get searchTitle => 'Search users';

  @override
  String get searchHint => 'Username...';

  @override
  String get searchNoResults => 'No users found';

  @override
  String get searchTypeToSearch => 'Type a name to search';

  @override
  String get profileTitle => 'Music profile';

  @override
  String get profileStartChat => 'Chat';

  @override
  String get profileNoData => 'This user doesn\'t have music data yet';

  @override
  String get profileTopArtists => 'Top Artists';

  @override
  String get profileTopGenres => 'Top Genres';

  @override
  String get profileCompatible => 'compatible';

  @override
  String get profileSharedArtists => 'Artists in common';

  @override
  String get profileSharedGenres => 'Genres in common';

  @override
  String get chatWriteMessage => 'Write a message...';

  @override
  String get chatSearchSong => 'Search song...';

  @override
  String get chatShareSong => 'Share song';

  @override
  String get chatDeletedUser =>
      'This account has been deleted. You can no longer send messages.';

  @override
  String get chatBlockedCannotSend =>
      'You can view the history, but you cannot send messages in this chat.';

  @override
  String get chatNotFriendsCannotSend =>
      'You can view the history, but only friends can send messages in this chat.';

  @override
  String get chatSendFirst => 'Send the first message';

  @override
  String get chatTypeToSearch => 'Type to search songs';

  @override
  String get chatNoResults => 'No results';

  @override
  String get chatDeleteTitle => 'Delete conversation';

  @override
  String get chatDeleteBody => 'This conversation will be deleted.';

  @override
  String get chatDeleteConfirm => 'Delete';

  @override
  String get chatDeleteCancel => 'Cancel';

  @override
  String get chatDateToday => 'Today';

  @override
  String get chatDateYesterday => 'Yesterday';

  @override
  String get statsTracks => 'Tracks';

  @override
  String get statsArtists => 'Artists';

  @override
  String get statsGenres => 'Genres';

  @override
  String get statsShortTerm => '4 weeks';

  @override
  String get statsMediumTerm => '6 months';

  @override
  String get statsLongTerm => '1 year';

  @override
  String statsError(String error) {
    return 'Error: $error';
  }

  @override
  String get statsEditArtists => 'Edit artists';

  @override
  String get statsNoData => 'No data available';

  @override
  String get statsOfflineCache => 'Offline — showing saved data';

  @override
  String get statsStaleCache => 'Showing data from over 48 hours ago';

  @override
  String get statsOfflineNoData =>
      'No connection and no saved data yet.\nVisit this tab online first.';

  @override
  String get socialNow => 'Now';

  @override
  String socialMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String socialDays(int days) {
    return '${days}d';
  }

  @override
  String get socialNoChats => 'No conversations yet';

  @override
  String get socialNoChatsHint => 'Search for users to start chatting';

  @override
  String get socialErrorLoading => 'Error loading conversations';

  @override
  String get socialUser => 'User';

  @override
  String get artistSelectorTitle => 'My Top Artists';

  @override
  String artistSelectorSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artists · the more you add, the better your matches',
      one: '1 artist · the more you add, the better your matches',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorSearchHint => 'Search artists...';

  @override
  String get artistSelectorContinue => 'Continue';

  @override
  String artistSelectorContinueLocked(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Add $remaining more artists',
      one: 'Add 1 more artist',
    );
    return '$_temp0';
  }

  @override
  String get artistSelectorNoResults => 'No artists found';

  @override
  String get artistSelectorEmpty =>
      'Search for your favourite artists to get started';

  @override
  String get artistSelectorSuggested => 'Suggested';

  @override
  String get artistSelectorStageBasic => 'Basic';

  @override
  String get artistSelectorStageGood => 'Good';

  @override
  String get artistSelectorStageGreat => 'Great';

  @override
  String get artistSelectorStageExpert => 'Expert';

  @override
  String get artistSelectorStageHint =>
      'Add more to improve your recommendations';

  @override
  String get menuProfile => 'My profile';

  @override
  String get menuAccountOptions => 'Account options';

  @override
  String get menuLightMode => 'Light mode';

  @override
  String get menuDarkMode => 'Dark mode';

  @override
  String get menuSignOut => 'Sign out';

  @override
  String get signingOut => 'Signing out...';

  @override
  String discoverySharedArtists(String artists) {
    return 'Artists in common: $artists';
  }

  @override
  String discoverySharedGenres(String genres) {
    return 'Genres in common: $genres';
  }

  @override
  String discoveryCompatible(String score) {
    return '$score% compatible';
  }

  @override
  String get friendsReceivedRequests => 'Received requests';

  @override
  String get friendsSentRequests => 'Sent requests';

  @override
  String get friendsMyFriends => 'My friends';

  @override
  String get friendsAccept => 'Accept';

  @override
  String get friendsReject => 'Reject';

  @override
  String get friendsCancel => 'Cancel';

  @override
  String get friendsSendRequest => 'Send request';

  @override
  String get friendsRequestSent => 'Request sent';

  @override
  String get friendsNoRequests => 'No pending requests';

  @override
  String get friendsNoFriends => 'No friends yet';

  @override
  String get friendsNoFriendsHint => 'Search for users to add friends';

  @override
  String get friendsRemove => 'Remove friend';

  @override
  String get friendsRemoveBody =>
      'This person will be removed from your friends list.';

  @override
  String get friendsAlreadyFriends => 'Already friends';

  @override
  String get profileAddFriend => 'Add friend';

  @override
  String get dailySongTitle => 'Song of the day';

  @override
  String get dailySongYourTitle => 'Your song of the day';

  @override
  String get dailySongChoose => 'Choose your song of the day';

  @override
  String dailySongBy(String artist) {
    return 'by $artist';
  }

  @override
  String get discoverTabPeople => 'Discover people';

  @override
  String get dailySongNone => 'You haven\'t chosen your song of the day yet';

  @override
  String get dailySongNoneHint =>
      'Share with others what you\'re listening to today';

  @override
  String get dailySongFriendsTitle => 'Your friends\' songs';

  @override
  String get dailySongFriendsNone =>
      'Your friends haven\'t chosen a song of the day yet';

  @override
  String get dailySongNoFriends => 'Add friends to see their song of the day';

  @override
  String get onboardingDiscoverTitle => 'Discover people';

  @override
  String get onboardingDiscoverDesc =>
      'MusiLink connects you with people who share your music taste. See how compatible you are based on your favourite artists.';

  @override
  String get onboardingProfileTitle => 'Build your music profile';

  @override
  String get onboardingProfileDesc =>
      'Add the artists you love most. The more you add, the better your matches — and the more people you\'ll discover.';

  @override
  String get onboardingConnectTitle => 'Chat, share, connect';

  @override
  String get onboardingConnectDesc =>
      'Connect with friends, chat about music, and share your song of the day.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Let\'s go';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get photoSetupTitle => 'Add a profile photo';

  @override
  String get photoSetupSubtitle =>
      'Let others know who you are. You can always change it later.';

  @override
  String get photoSetupChoose => 'Choose photo';

  @override
  String get photoSetupChange => 'Change photo';

  @override
  String get photoSetupContinue => 'Continue';

  @override
  String get photoSetupSkip => 'Skip for now';

  @override
  String get photoSetupUploading => 'Uploading...';

  @override
  String get photoSetupGallery => 'Gallery';

  @override
  String get photoSetupCamera => 'Camera';

  @override
  String get photoSetupError => 'Could not upload photo. Please try again.';

  @override
  String get blockUserBlock => 'Block user';

  @override
  String get blockUserUnblock => 'Unblock';

  @override
  String blockUserBlockConfirmTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get blockUserBlockConfirmBody =>
      'They will be removed from your friends list and won\'t appear in your discovery.';

  @override
  String get blockUserBlockConfirm => 'Block';

  @override
  String blockUserBlockedSnackbar(String name) {
    return '$name has been blocked';
  }

  @override
  String blockUserUnblockedSnackbar(String name) {
    return '$name has been unblocked';
  }

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsBlockedUsers => 'Blocked users';

  @override
  String get blockedUsersTitle => 'Blocked users';

  @override
  String get blockedUsersEmpty => 'You haven\'t blocked any users';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsVibration => 'Vibration';

  @override
  String get settingsSound => 'Sound';

  @override
  String get pushNotificationsTitle => 'Don\'t miss a message';

  @override
  String get pushNotificationsBody =>
      'Enable notifications to receive messages and friend requests even when MusiLink is closed.';

  @override
  String get pushNotificationsEnable => 'Enable notifications';

  @override
  String get pushNotificationsInstallBody =>
      'On iPhone, open MusiLink in Safari, tap Share and choose “Add to Home Screen”. Then open the app from its icon.';

  @override
  String get pushNotificationsBlockedBody =>
      'Notifications are blocked. You can enable them in iPhone Settings → Notifications → MusiLink.';

  @override
  String get pushNotificationsUnsupportedBody =>
      'This browser or device does not support web notifications.';

  @override
  String get pushNotificationsError =>
      'Notifications could not be enabled. Please try again.';

  @override
  String get settingsLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get deleteAccountBody =>
      'This will permanently delete your account, your messages, your reactions, your photo, your music data and your profile information. This action cannot be undone.';

  @override
  String get deleteAccountConfirm => 'Delete';

  @override
  String get deletingAccount => 'Deleting account...';

  @override
  String get reauthTitle => 'Confirm your identity';

  @override
  String get reauthBody => 'To delete your account, re-enter your password.';

  @override
  String get reauthConfirm => 'Confirm';

  @override
  String get reauthWrongAccount =>
      'The selected account is not linked to this app. Please choose the correct account.';

  @override
  String get privacyTitle => 'Privacy Policy';

  @override
  String get privacyLastUpdated => 'Last updated: 5 May 2026';

  @override
  String get privacyS1Title => '1. Data Controller';

  @override
  String get privacyS1Body =>
      'MusiLink is developed and operated by Pablo Armas (armasp80@gmail.com), established in Spain. Pablo Armas is the data controller responsible for processing your personal data in accordance with Regulation (EU) 2016/679 (GDPR).';

  @override
  String get privacyS2Title => '2. Data We Collect';

  @override
  String get privacyS2Body =>
      'We collect and process the following personal data:\n\n• Account data: name, email address, profile photo, and login identifiers (via email/password or Google Sign-In).\n\n• Music profile data: top artists you select, inferred top genres, daily song selections, and shared songs.\n\n• Social data: messages, friend requests, and emoji reactions.\n\n• Technical data: crash reports collected by Firebase Crashlytics and usage events collected by Firebase Analytics.';

  @override
  String get privacyS3Title => '3. How We Use Your Data';

  @override
  String get privacyS3Body =>
      'Your data is processed for the following purposes:\n\n• Providing the service (account, music compatibility, discovery, chat). Legal basis: contract performance (Art. 6.1.b GDPR).\n\n• Music profile features: displaying and comparing your selected music taste. Legal basis: contract performance (Art. 6.1.b GDPR).\n\n• App stability: diagnosing crashes and errors. Legal basis: legitimate interest (Art. 6.1.f GDPR).\n\n• App improvement: understanding how users interact with the App to improve it. Legal basis: legitimate interest (Art. 6.1.f GDPR).';

  @override
  String get privacyS4Title => '4. Third-Party Services';

  @override
  String get privacyS4Body =>
      'We use the following third-party services, each with their own privacy policies:\n\n• Google Firebase Firestore, Crashlytics and Analytics — Google LLC. Your profile data, messages, and usage events are stored on servers in the European region (europe-southwest1).\n\n• Google Firebase Storage — Google LLC. Profile photos are stored on servers located in the United States under standard contractual clauses (Art. 46 GDPR).\n\n• Cloud Functions — Google LLC. Your message and friend request data is processed on servers in the European region (europe-southwest1).\n\n• Spotify and Last.fm. Used as music catalogue providers for artist/song search and artist suggestions. No Spotify account connection is required.';

  @override
  String get privacyS5Title => '5. Data Retention & Deletion';

  @override
  String get privacyS5Body =>
      'We do not retain your data beyond the time you use the App. When you delete your account via the \'Delete account\' button in Settings, we delete your private data, profile photo, relationships, requests, tokens, preferences, and music data. The public profile is replaced with an anonymous placeholder so technical references do not break. Messages you sent are removed from conversations and your reactions are removed; if a conversation becomes empty, it is deleted. Some technical records, crash reports, or analytics data held by Google may be subject to Google\'s own retention policies.';

  @override
  String get privacyS6Title => '6. Your Rights';

  @override
  String get privacyS6Body =>
      'Under GDPR, you have the following rights:\n\n• Access: request a copy of data we hold about you.\n• Rectification: correct inaccurate or incomplete data.\n• Erasure: delete your account and all data via the \'Delete account\' button in Settings.\n• Restriction: request we limit processing of your data.\n• Portability: receive your data in a structured, machine-readable format.\n• Objection: object to processing based on legitimate interest.\n\nTo exercise these rights, contact armasp80@gmail.com. You may also file a complaint with the Spanish Data Protection Authority (AEPD) at www.aepd.es.';

  @override
  String get privacyS7Title => '7. Minimum Age';

  @override
  String get privacyS7Body =>
      'MusiLink is intended for users aged 16 and over. We do not knowingly collect personal data from anyone under 16. If you believe a minor has provided us with personal data, contact us at armasp80@gmail.com and we will delete it immediately.';

  @override
  String get privacyS8Title => '8. Security';

  @override
  String get privacyS8Body =>
      'We implement appropriate technical and organisational measures to protect your personal data against unauthorised access, loss, or alteration. Data is stored in Google Firebase, which applies industry-standard security controls.';

  @override
  String get privacyS9Title => '9. Contact';

  @override
  String get privacyS9Body =>
      'For any questions about this Privacy Policy or the processing of your data, please contact:\n\nPablo Armas\narmasp80@gmail.com';

  @override
  String get privacyS10Title => '10. International Data Transfers';

  @override
  String get privacyS10Body =>
      'Profile photos are stored in Google Firebase Storage with servers located in the United States. By using the App, you explicitly authorise this international data transfer of image data. Google has implemented the necessary technical and organisational measures under the Standard Contractual Clauses approved by the European Commission (Art. 46 GDPR) to ensure an adequate level of protection equivalent to that in the EU.\n\nYour personal data, messages, and music profile data are stored on servers located in the European region (europe-southwest1), within the EU.';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'A new version of MusiLink is required to continue. Update now to keep your account and chats working securely.';

  @override
  String updateCurrentVersion(String version, int build) {
    return 'Installed version: $version ($build)';
  }

  @override
  String get updateNowButton => 'Update now';

  @override
  String get updateRetryButton => 'Check again';

  @override
  String get updateStoreOpenError =>
      'We couldn\'t open the store. Check your connection and try again.';
}
