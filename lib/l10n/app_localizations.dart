import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_el.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('el'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
  ];

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'Connect with people who share your music taste'**
  String get authTagline;

  /// No description provided for @authName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authName;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authEnterName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get authEnterName;

  /// No description provided for @authEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEnterEmail;

  /// No description provided for @authInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get authInvalidEmail;

  /// No description provided for @authEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authEnterPassword;

  /// No description provided for @authMinChars.
  ///
  /// In en, this message translates to:
  /// **'Minimum 6 characters'**
  String get authMinChars;

  /// No description provided for @authErrorEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered.'**
  String get authErrorEmailInUse;

  /// No description provided for @authErrorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email.'**
  String get authErrorInvalidEmail;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'No account found with this email.'**
  String get authErrorUserNotFound;

  /// No description provided for @authErrorWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password.'**
  String get authErrorWrongPassword;

  /// No description provided for @authErrorInvalidCredential.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials.'**
  String get authErrorInvalidCredential;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment.'**
  String get authErrorTooManyRequests;

  /// No description provided for @authErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Authentication error ({code}).'**
  String authErrorGeneric(String code);

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// No description provided for @authContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueGoogle;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authHaveAccount;

  /// No description provided for @authRegister.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authRegister;

  /// No description provided for @authLogin.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLogin;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authPasswordResetSent.
  ///
  /// In en, this message translates to:
  /// **'If this email has a password account, we sent you a reset link.'**
  String get authPasswordResetSent;

  /// No description provided for @authErrorCouldNotAuth.
  ///
  /// In en, this message translates to:
  /// **'Could not authenticate. Please try again.'**
  String get authErrorCouldNotAuth;

  /// No description provided for @authErrorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error. Please try again.'**
  String get authErrorUnexpected;

  /// No description provided for @authErrorGoogleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Could not sign in with Google.'**
  String get authErrorGoogleSignIn;

  /// No description provided for @authErrorGoogleSignInGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error signing in with Google.'**
  String get authErrorGoogleSignInGeneric;

  /// No description provided for @authErrorAccountExistsWithDifferentCredential.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered with a password. Please sign in with email and password.'**
  String get authErrorAccountExistsWithDifferentCredential;

  /// No description provided for @authUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// No description provided for @authEnterUsername.
  ///
  /// In en, this message translates to:
  /// **'Choose a username'**
  String get authEnterUsername;

  /// No description provided for @authUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'lowercase letters, numbers and _'**
  String get authUsernameHint;

  /// No description provided for @authUsernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least 3 characters'**
  String get authUsernameTooShort;

  /// No description provided for @authUsernameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Max 20 characters'**
  String get authUsernameTooLong;

  /// No description provided for @authUsernameInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Only letters, numbers and _'**
  String get authUsernameInvalidChars;

  /// No description provided for @authUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'This username is already taken'**
  String get authUsernameTaken;

  /// No description provided for @authUsernameAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get authUsernameAvailable;

  /// No description provided for @authUsernameChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get authUsernameChecking;

  /// No description provided for @usernameSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your username'**
  String get usernameSetupTitle;

  /// No description provided for @usernameSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is how others will find you on MusiLink.'**
  String get usernameSetupSubtitle;

  /// No description provided for @usernameSetupButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get usernameSetupButton;

  /// No description provided for @discoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover people'**
  String get discoverTitle;

  /// No description provided for @discoverErrorLoading.
  ///
  /// In en, this message translates to:
  /// **'Error loading discovery'**
  String get discoverErrorLoading;

  /// No description provided for @discoverNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No users with music data'**
  String get discoverNoUsers;

  /// No description provided for @discoverNoUsersHint.
  ///
  /// In en, this message translates to:
  /// **'As more users create their music profile, they will appear here'**
  String get discoverNoUsersHint;

  /// No description provided for @navDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navDiscover;

  /// No description provided for @navStats.
  ///
  /// In en, this message translates to:
  /// **'My Top'**
  String get navStats;

  /// No description provided for @navMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get navMessages;

  /// No description provided for @navFriends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get navFriends;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search users'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Username...'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get searchNoResults;

  /// No description provided for @searchTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type a name to search'**
  String get searchTypeToSearch;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Music profile'**
  String get profileTitle;

  /// No description provided for @profileStartChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get profileStartChat;

  /// No description provided for @profileNoData.
  ///
  /// In en, this message translates to:
  /// **'This user doesn\'t have music data yet'**
  String get profileNoData;

  /// No description provided for @profileTopArtists.
  ///
  /// In en, this message translates to:
  /// **'Top Artists'**
  String get profileTopArtists;

  /// No description provided for @profileTopGenres.
  ///
  /// In en, this message translates to:
  /// **'Top Genres'**
  String get profileTopGenres;

  /// No description provided for @profileCompatible.
  ///
  /// In en, this message translates to:
  /// **'compatible'**
  String get profileCompatible;

  /// No description provided for @profileSharedArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists in common'**
  String get profileSharedArtists;

  /// No description provided for @profileSharedGenres.
  ///
  /// In en, this message translates to:
  /// **'Genres in common'**
  String get profileSharedGenres;

  /// No description provided for @chatWriteMessage.
  ///
  /// In en, this message translates to:
  /// **'Write a message...'**
  String get chatWriteMessage;

  /// No description provided for @chatSearchSong.
  ///
  /// In en, this message translates to:
  /// **'Search song...'**
  String get chatSearchSong;

  /// No description provided for @chatShareSong.
  ///
  /// In en, this message translates to:
  /// **'Share song'**
  String get chatShareSong;

  /// No description provided for @chatDeletedUser.
  ///
  /// In en, this message translates to:
  /// **'This account has been deleted. You can no longer send messages.'**
  String get chatDeletedUser;

  /// No description provided for @chatBlockedCannotSend.
  ///
  /// In en, this message translates to:
  /// **'You can view the history, but you cannot send messages in this chat.'**
  String get chatBlockedCannotSend;

  /// No description provided for @chatSendFirst.
  ///
  /// In en, this message translates to:
  /// **'Send the first message'**
  String get chatSendFirst;

  /// No description provided for @chatTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search songs'**
  String get chatTypeToSearch;

  /// No description provided for @chatNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get chatNoResults;

  /// No description provided for @statsTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get statsTracks;

  /// No description provided for @statsArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get statsArtists;

  /// No description provided for @statsGenres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get statsGenres;

  /// No description provided for @statsShortTerm.
  ///
  /// In en, this message translates to:
  /// **'4 weeks'**
  String get statsShortTerm;

  /// No description provided for @statsMediumTerm.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get statsMediumTerm;

  /// No description provided for @statsLongTerm.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get statsLongTerm;

  /// No description provided for @statsError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String statsError(String error);

  /// No description provided for @statsEditArtists.
  ///
  /// In en, this message translates to:
  /// **'Edit artists'**
  String get statsEditArtists;

  /// No description provided for @statsNoData.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get statsNoData;

  /// No description provided for @statsOfflineCache.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved data'**
  String get statsOfflineCache;

  /// No description provided for @statsStaleCache.
  ///
  /// In en, this message translates to:
  /// **'Showing data from over 48 hours ago'**
  String get statsStaleCache;

  /// No description provided for @statsOfflineNoData.
  ///
  /// In en, this message translates to:
  /// **'No connection and no saved data yet.\nVisit this tab online first.'**
  String get statsOfflineNoData;

  /// No description provided for @socialNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get socialNow;

  /// No description provided for @socialMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String socialMinutes(int minutes);

  /// No description provided for @socialDays.
  ///
  /// In en, this message translates to:
  /// **'{days}d'**
  String socialDays(int days);

  /// No description provided for @socialNoChats.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get socialNoChats;

  /// No description provided for @socialNoChatsHint.
  ///
  /// In en, this message translates to:
  /// **'Search for users to start chatting'**
  String get socialNoChatsHint;

  /// No description provided for @socialErrorLoading.
  ///
  /// In en, this message translates to:
  /// **'Error loading conversations'**
  String get socialErrorLoading;

  /// No description provided for @socialUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get socialUser;

  /// No description provided for @artistSelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'My Top Artists'**
  String get artistSelectorTitle;

  /// No description provided for @artistSelectorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 artist · the more you add, the better your matches} other{{count} artists · the more you add, the better your matches}}'**
  String artistSelectorSubtitle(int count);

  /// No description provided for @artistSelectorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search artists...'**
  String get artistSelectorSearchHint;

  /// No description provided for @artistSelectorContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get artistSelectorContinue;

  /// No description provided for @artistSelectorContinueLocked.
  ///
  /// In en, this message translates to:
  /// **'{remaining, plural, =1{Add 1 more artist} other{Add {remaining} more artists}}'**
  String artistSelectorContinueLocked(int remaining);

  /// No description provided for @artistSelectorNoResults.
  ///
  /// In en, this message translates to:
  /// **'No artists found'**
  String get artistSelectorNoResults;

  /// No description provided for @artistSelectorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Search for your favourite artists to get started'**
  String get artistSelectorEmpty;

  /// No description provided for @artistSelectorSuggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get artistSelectorSuggested;

  /// No description provided for @artistSelectorStageBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get artistSelectorStageBasic;

  /// No description provided for @artistSelectorStageGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get artistSelectorStageGood;

  /// No description provided for @artistSelectorStageGreat.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get artistSelectorStageGreat;

  /// No description provided for @artistSelectorStageExpert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get artistSelectorStageExpert;

  /// No description provided for @artistSelectorStageHint.
  ///
  /// In en, this message translates to:
  /// **'Add more to improve your recommendations'**
  String get artistSelectorStageHint;

  /// No description provided for @menuProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get menuProfile;

  /// No description provided for @menuAccountOptions.
  ///
  /// In en, this message translates to:
  /// **'Account options'**
  String get menuAccountOptions;

  /// No description provided for @menuLightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get menuLightMode;

  /// No description provided for @menuDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get menuDarkMode;

  /// No description provided for @menuSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get menuSignOut;

  /// No description provided for @signingOut.
  ///
  /// In en, this message translates to:
  /// **'Signing out...'**
  String get signingOut;

  /// No description provided for @discoverySharedArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists in common: {artists}'**
  String discoverySharedArtists(String artists);

  /// No description provided for @discoverySharedGenres.
  ///
  /// In en, this message translates to:
  /// **'Genres in common: {genres}'**
  String discoverySharedGenres(String genres);

  /// No description provided for @discoveryCompatible.
  ///
  /// In en, this message translates to:
  /// **'{score}% compatible'**
  String discoveryCompatible(String score);

  /// No description provided for @friendsReceivedRequests.
  ///
  /// In en, this message translates to:
  /// **'Received requests'**
  String get friendsReceivedRequests;

  /// No description provided for @friendsSentRequests.
  ///
  /// In en, this message translates to:
  /// **'Sent requests'**
  String get friendsSentRequests;

  /// No description provided for @friendsMyFriends.
  ///
  /// In en, this message translates to:
  /// **'My friends'**
  String get friendsMyFriends;

  /// No description provided for @friendsAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get friendsAccept;

  /// No description provided for @friendsReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get friendsReject;

  /// No description provided for @friendsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get friendsCancel;

  /// No description provided for @friendsSendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get friendsSendRequest;

  /// No description provided for @friendsRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get friendsRequestSent;

  /// No description provided for @friendsNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get friendsNoRequests;

  /// No description provided for @friendsNoFriends.
  ///
  /// In en, this message translates to:
  /// **'No friends yet'**
  String get friendsNoFriends;

  /// No description provided for @friendsNoFriendsHint.
  ///
  /// In en, this message translates to:
  /// **'Search for users to add friends'**
  String get friendsNoFriendsHint;

  /// No description provided for @friendsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove friend'**
  String get friendsRemove;

  /// No description provided for @friendsRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'This person will be removed from your friends list.'**
  String get friendsRemoveBody;

  /// No description provided for @friendsAlreadyFriends.
  ///
  /// In en, this message translates to:
  /// **'Already friends'**
  String get friendsAlreadyFriends;

  /// No description provided for @profileAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add friend'**
  String get profileAddFriend;

  /// No description provided for @dailySongTitle.
  ///
  /// In en, this message translates to:
  /// **'Song of the day'**
  String get dailySongTitle;

  /// No description provided for @dailySongYourTitle.
  ///
  /// In en, this message translates to:
  /// **'Your song of the day'**
  String get dailySongYourTitle;

  /// No description provided for @dailySongChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose your song of the day'**
  String get dailySongChoose;

  /// No description provided for @dailySongBy.
  ///
  /// In en, this message translates to:
  /// **'by {artist}'**
  String dailySongBy(String artist);

  /// No description provided for @discoverTabPeople.
  ///
  /// In en, this message translates to:
  /// **'Discover people'**
  String get discoverTabPeople;

  /// No description provided for @dailySongNone.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t chosen your song of the day yet'**
  String get dailySongNone;

  /// No description provided for @dailySongNoneHint.
  ///
  /// In en, this message translates to:
  /// **'Share with others what you\'re listening to today'**
  String get dailySongNoneHint;

  /// No description provided for @dailySongFriendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your friends\' songs'**
  String get dailySongFriendsTitle;

  /// No description provided for @dailySongFriendsNone.
  ///
  /// In en, this message translates to:
  /// **'Your friends haven\'t chosen a song of the day yet'**
  String get dailySongFriendsNone;

  /// No description provided for @dailySongNoFriends.
  ///
  /// In en, this message translates to:
  /// **'Add friends to see their song of the day'**
  String get dailySongNoFriends;

  /// No description provided for @onboardingDiscoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover people'**
  String get onboardingDiscoverTitle;

  /// No description provided for @onboardingDiscoverDesc.
  ///
  /// In en, this message translates to:
  /// **'MusiLink connects you with people who share your music taste. See how compatible you are based on your favourite artists.'**
  String get onboardingDiscoverDesc;

  /// No description provided for @onboardingProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Build your music profile'**
  String get onboardingProfileTitle;

  /// No description provided for @onboardingProfileDesc.
  ///
  /// In en, this message translates to:
  /// **'Add the artists you love most. The more you add, the better your matches — and the more people you\'ll discover.'**
  String get onboardingProfileDesc;

  /// No description provided for @onboardingConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat, share, connect'**
  String get onboardingConnectTitle;

  /// No description provided for @onboardingConnectDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect with friends, chat about music, and share your song of the day.'**
  String get onboardingConnectDesc;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Let\'s go'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @photoSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a profile photo'**
  String get photoSetupTitle;

  /// No description provided for @photoSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let others know who you are. You can always change it later.'**
  String get photoSetupSubtitle;

  /// No description provided for @photoSetupChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose photo'**
  String get photoSetupChoose;

  /// No description provided for @photoSetupChange.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get photoSetupChange;

  /// No description provided for @photoSetupContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get photoSetupContinue;

  /// No description provided for @photoSetupSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get photoSetupSkip;

  /// No description provided for @photoSetupUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get photoSetupUploading;

  /// No description provided for @photoSetupGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get photoSetupGallery;

  /// No description provided for @photoSetupCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get photoSetupCamera;

  /// No description provided for @photoSetupError.
  ///
  /// In en, this message translates to:
  /// **'Could not upload photo. Please try again.'**
  String get photoSetupError;

  /// No description provided for @blockUserBlock.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get blockUserBlock;

  /// No description provided for @blockUserUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get blockUserUnblock;

  /// No description provided for @blockUserBlockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String blockUserBlockConfirmTitle(String name);

  /// No description provided for @blockUserBlockConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They will be removed from your friends list and won\'t appear in your discovery.'**
  String get blockUserBlockConfirmBody;

  /// No description provided for @blockUserBlockConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockUserBlockConfirm;

  /// No description provided for @blockUserBlockedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{name} has been blocked'**
  String blockUserBlockedSnackbar(String name);

  /// No description provided for @blockUserUnblockedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{name} has been unblocked'**
  String blockUserUnblockedSnackbar(String name);

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get settingsBlockedUsers;

  /// No description provided for @blockedUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get blockedUsersTitle;

  /// No description provided for @blockedUsersEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t blocked any users'**
  String get blockedUsersEmpty;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericError;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsVibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get settingsVibration;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// No description provided for @settingsLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsLegal;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account, your messages, your reactions, your photo, your music data and your profile information. This action cannot be undone.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountConfirm;

  /// No description provided for @deletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleting account...'**
  String get deletingAccount;

  /// No description provided for @reauthTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity'**
  String get reauthTitle;

  /// No description provided for @reauthBody.
  ///
  /// In en, this message translates to:
  /// **'To delete your account, re-enter your password.'**
  String get reauthBody;

  /// No description provided for @reauthConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get reauthConfirm;

  /// No description provided for @reauthWrongAccount.
  ///
  /// In en, this message translates to:
  /// **'The selected account is not linked to this app. Please choose the correct account.'**
  String get reauthWrongAccount;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyTitle;

  /// No description provided for @privacyLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated: 5 May 2026'**
  String get privacyLastUpdated;

  /// No description provided for @privacyS1Title.
  ///
  /// In en, this message translates to:
  /// **'1. Data Controller'**
  String get privacyS1Title;

  /// No description provided for @privacyS1Body.
  ///
  /// In en, this message translates to:
  /// **'MusiLink is developed and operated by Pablo Armas (armasp80@gmail.com), established in Spain. Pablo Armas is the data controller responsible for processing your personal data in accordance with Regulation (EU) 2016/679 (GDPR).'**
  String get privacyS1Body;

  /// No description provided for @privacyS2Title.
  ///
  /// In en, this message translates to:
  /// **'2. Data We Collect'**
  String get privacyS2Title;

  /// No description provided for @privacyS2Body.
  ///
  /// In en, this message translates to:
  /// **'We collect and process the following personal data:\n\n• Account data: name, email address, profile photo, and login identifiers (via email/password or Google Sign-In).\n\n• Music profile data: top artists you select, inferred top genres, daily song selections, and shared songs.\n\n• Social data: messages, friend requests, and emoji reactions.\n\n• Technical data: crash reports collected by Firebase Crashlytics and usage events collected by Firebase Analytics.'**
  String get privacyS2Body;

  /// No description provided for @privacyS3Title.
  ///
  /// In en, this message translates to:
  /// **'3. How We Use Your Data'**
  String get privacyS3Title;

  /// No description provided for @privacyS3Body.
  ///
  /// In en, this message translates to:
  /// **'Your data is processed for the following purposes:\n\n• Providing the service (account, music compatibility, discovery, chat). Legal basis: contract performance (Art. 6.1.b GDPR).\n\n• Music profile features: displaying and comparing your selected music taste. Legal basis: contract performance (Art. 6.1.b GDPR).\n\n• App stability: diagnosing crashes and errors. Legal basis: legitimate interest (Art. 6.1.f GDPR).\n\n• App improvement: understanding how users interact with the App to improve it. Legal basis: legitimate interest (Art. 6.1.f GDPR).'**
  String get privacyS3Body;

  /// No description provided for @privacyS4Title.
  ///
  /// In en, this message translates to:
  /// **'4. Third-Party Services'**
  String get privacyS4Title;

  /// No description provided for @privacyS4Body.
  ///
  /// In en, this message translates to:
  /// **'We use the following third-party services, each with their own privacy policies:\n\n• Google Firebase Firestore, Crashlytics and Analytics — Google LLC. Your profile data, messages, and usage events are stored on servers in the European region (europe-southwest1).\n\n• Google Firebase Storage — Google LLC. Profile photos are stored on servers located in the United States under standard contractual clauses (Art. 46 GDPR).\n\n• Cloud Functions — Google LLC. Your message and friend request data is processed on servers in the European region (europe-southwest1).\n\n• Spotify and Last.fm. Used as music catalogue providers for artist/song search and artist suggestions. No Spotify account connection is required.'**
  String get privacyS4Body;

  /// No description provided for @privacyS5Title.
  ///
  /// In en, this message translates to:
  /// **'5. Data Retention & Deletion'**
  String get privacyS5Title;

  /// No description provided for @privacyS5Body.
  ///
  /// In en, this message translates to:
  /// **'We do not retain your data beyond the time you use the App. When you delete your account via the \'Delete account\' button in Settings, we delete your private data, profile photo, relationships, requests, tokens, preferences, and music data. The public profile is replaced with an anonymous placeholder so technical references do not break. Messages you sent are removed from conversations and your reactions are removed; if a conversation becomes empty, it is deleted. Some technical records, crash reports, or analytics data held by Google may be subject to Google\'s own retention policies.'**
  String get privacyS5Body;

  /// No description provided for @privacyS6Title.
  ///
  /// In en, this message translates to:
  /// **'6. Your Rights'**
  String get privacyS6Title;

  /// No description provided for @privacyS6Body.
  ///
  /// In en, this message translates to:
  /// **'Under GDPR, you have the following rights:\n\n• Access: request a copy of data we hold about you.\n• Rectification: correct inaccurate or incomplete data.\n• Erasure: delete your account and all data via the \'Delete account\' button in Settings.\n• Restriction: request we limit processing of your data.\n• Portability: receive your data in a structured, machine-readable format.\n• Objection: object to processing based on legitimate interest.\n\nTo exercise these rights, contact armasp80@gmail.com. You may also file a complaint with the Spanish Data Protection Authority (AEPD) at www.aepd.es.'**
  String get privacyS6Body;

  /// No description provided for @privacyS7Title.
  ///
  /// In en, this message translates to:
  /// **'7. Minimum Age'**
  String get privacyS7Title;

  /// No description provided for @privacyS7Body.
  ///
  /// In en, this message translates to:
  /// **'MusiLink is intended for users aged 16 and over. We do not knowingly collect personal data from anyone under 16. If you believe a minor has provided us with personal data, contact us at armasp80@gmail.com and we will delete it immediately.'**
  String get privacyS7Body;

  /// No description provided for @privacyS8Title.
  ///
  /// In en, this message translates to:
  /// **'8. Security'**
  String get privacyS8Title;

  /// No description provided for @privacyS8Body.
  ///
  /// In en, this message translates to:
  /// **'We implement appropriate technical and organisational measures to protect your personal data against unauthorised access, loss, or alteration. Data is stored in Google Firebase, which applies industry-standard security controls.'**
  String get privacyS8Body;

  /// No description provided for @privacyS9Title.
  ///
  /// In en, this message translates to:
  /// **'9. Contact'**
  String get privacyS9Title;

  /// No description provided for @privacyS9Body.
  ///
  /// In en, this message translates to:
  /// **'For any questions about this Privacy Policy or the processing of your data, please contact:\n\nPablo Armas\narmasp80@gmail.com'**
  String get privacyS9Body;

  /// No description provided for @privacyS10Title.
  ///
  /// In en, this message translates to:
  /// **'10. International Data Transfers'**
  String get privacyS10Title;

  /// No description provided for @privacyS10Body.
  ///
  /// In en, this message translates to:
  /// **'Profile photos are stored in Google Firebase Storage with servers located in the United States. By using the App, you explicitly authorise this international data transfer of image data. Google has implemented the necessary technical and organisational measures under the Standard Contractual Clauses approved by the European Commission (Art. 46 GDPR) to ensure an adequate level of protection equivalent to that in the EU.\n\nYour personal data, messages, and music profile data are stored on servers located in the European region (europe-southwest1), within the EU.'**
  String get privacyS10Body;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['el', 'en', 'es', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
