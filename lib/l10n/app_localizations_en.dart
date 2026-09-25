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
  String get authErrorGoogleSignInGeneric => 'Error signing in with Google.';

  @override
  String get authErrorAccountExistsWithDifferentCredential =>
      'This email is already registered with a password. Please sign in with email and password.';

  @override
  String get authPrivacyLink => 'Privacy Policy';

  @override
  String get termsAcceptanceTitle => 'Terms and Conditions';

  @override
  String get termsAcceptanceIntro =>
      'To continue using MusiLink, please read and accept the terms.';

  @override
  String termsAcceptanceVersion(String version) {
    return 'Version $version';
  }

  @override
  String get termsOpenDocument => 'Read Terms and Conditions';

  @override
  String get termsAcceptCheckbox =>
      'I have read and accept MusiLink\'s Terms and Conditions.';

  @override
  String get termsAcceptAndContinue => 'Accept and continue';

  @override
  String get termsAccepting => 'Accepting…';

  @override
  String get termsSaveError =>
      'We could not save your acceptance. Please try again.';

  @override
  String get termsOpenError => 'Could not open the link.';

  @override
  String get authUsername => 'Username';

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
  String get chatDeleteConfirm => 'Delete';

  @override
  String get chatDeleteCancel => 'Cancel';

  @override
  String get chatDateToday => 'Today';

  @override
  String get chatDateYesterday => 'Yesterday';

  @override
  String get statsArtists => 'Artists';

  @override
  String get statsGenres => 'Genres';

  @override
  String get statsEditArtists => 'Edit artists';

  @override
  String get statsNoData => 'No data available';

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
  String artistSelectorSubtitle(int count, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count of $max artists selected · drag to rank',
      one: '1 of $max artists selected · drag to rank',
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
  String get menuAccountOptions => 'Account options';

  @override
  String get menuSignOut => 'Sign out';

  @override
  String get signingOut => 'Signing out...';

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
  String get profileAddFriend => 'Add friend';

  @override
  String get dailySongTitle => 'Song of the day';

  @override
  String get dailySongYourTitle => 'Your song of the day';

  @override
  String get dailySongChoose => 'Choose your song of the day';

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
  String get dailySongSaveError =>
      'The song couldn\'t be published. Check your connection and try again.';

  @override
  String get dailySongRefreshError =>
      'Couldn\'t refresh from the server. Previous data is still shown.';

  @override
  String get dailySongLoadError => 'Couldn\'t load the songs of the day.';

  @override
  String get dailySongReplyOutgoing => 'You replied to their song of the day';

  @override
  String get dailySongReplyIncoming => 'Replied to your song of the day';

  @override
  String get dailySongLikesTitle => 'Likes';

  @override
  String get dailySongNoLikes => 'Your song has no likes yet.';

  @override
  String get dailySongLike => 'Like';

  @override
  String get dailySongUnlike => 'Unlike';

  @override
  String get dailySongReply => 'Reply';

  @override
  String get dailySongReplyHint =>
      'Your reply will be sent privately in your chat with this friend.';

  @override
  String get dailySongReplySend => 'Send';

  @override
  String get dailySongReplySending => 'Sending…';

  @override
  String get dailySongReplySent => 'Reply sent to your chat.';

  @override
  String get dailySongInteractionError =>
      'Could not save. Check that you are still friends and the song is still available, then try again.';

  @override
  String get dailySongReplyTooLong => 'The reply is too long.';

  @override
  String get dailySongRetry => 'Try again';

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
  String get reportProfileAction => 'Report profile';

  @override
  String get reportMessageAction => 'Report message';

  @override
  String reportProfileTitle(String name) {
    return 'Report $name';
  }

  @override
  String get reportMessageTitle => 'Report message';

  @override
  String get reportReasonPrompt => 'Choose a reason for this report:';

  @override
  String get reportReasonSpam => 'Spam or misleading content';

  @override
  String get reportReasonHarassment => 'Harassment or threats';

  @override
  String get reportReasonSexualContent => 'Inappropriate sexual content';

  @override
  String get reportReasonHateSpeech => 'Hate or discrimination';

  @override
  String get reportReasonImpersonation => 'Impersonation';

  @override
  String get reportReasonOther => 'Another reason';

  @override
  String get reportSubmitted =>
      'Report sent. We\'ll review it as soon as possible.';

  @override
  String get reportAlreadySubmitted => 'You already reported this content.';

  @override
  String get reportSubmitError =>
      'The report couldn\'t be sent. Please try again.';

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
  String get settingsTheme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

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
      'On iPhone, open MusiLink in Safari, tap Share, then “More”, and choose “Add to Home Screen”. Then open the app from its icon.';

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
  String get pwaInstallTitle => 'Install MusiLink on your iPhone';

  @override
  String get pwaInstallBody =>
      'To receive notifications and enjoy the complete experience:';

  @override
  String get pwaInstallStepMore => 'Tap More (···) in the bottom-right corner.';

  @override
  String get pwaInstallStepShare => 'Tap Share.';

  @override
  String get pwaInstallStepSeeMore => 'Tap “More”.';

  @override
  String get pwaInstallStepAdd => 'Choose “Add to Home Screen”.';

  @override
  String get pwaInstallStepOpen => 'Open MusiLink from its new icon.';

  @override
  String get pwaInstallContinue => 'Continue in Safari';

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
  String get deletingAccount => 'Starting account deletion...';

  @override
  String get accountDeletionRequested =>
      'Your account deletion has started. You can close the app; the process will continue in the background.';

  @override
  String get accountDeletionPending =>
      'This account is currently being deleted. Please try again later.';

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
