"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.expireDailySongs = exports.onChatMessageDeleted = exports.onChatSoftDeleted = exports.onNewMessage = exports.onFriendRequestDeleted = exports.onFriendRequestAccepted = exports.onFriendRequest = exports.acceptFriendRequest = exports.onUserMusicProfileChanged = exports.onUserMusicProfileCreated = exports.createUserProfile = exports.processAccountDeletion = exports.requestAccountDeletion = exports.getSimilarArtists = exports.searchSpotifyTracks = exports.searchSpotifyArtists = void 0;
// Keep this file as the public Firebase Functions manifest. Domain logic lives
// in focused modules so importing one feature does not expose unrelated code.
var spotify_1 = require("./spotify");
Object.defineProperty(exports, "searchSpotifyArtists", { enumerable: true, get: function () { return spotify_1.searchSpotifyArtists; } });
Object.defineProperty(exports, "searchSpotifyTracks", { enumerable: true, get: function () { return spotify_1.searchSpotifyTracks; } });
var lastfm_1 = require("./lastfm");
Object.defineProperty(exports, "getSimilarArtists", { enumerable: true, get: function () { return lastfm_1.getSimilarArtists; } });
var account_deletion_1 = require("./account_deletion");
Object.defineProperty(exports, "requestAccountDeletion", { enumerable: true, get: function () { return account_deletion_1.requestAccountDeletion; } });
Object.defineProperty(exports, "processAccountDeletion", { enumerable: true, get: function () { return account_deletion_1.processAccountDeletion; } });
var user_profile_1 = require("./user_profile");
Object.defineProperty(exports, "createUserProfile", { enumerable: true, get: function () { return user_profile_1.createUserProfile; } });
var recommendations_1 = require("./recommendations");
Object.defineProperty(exports, "onUserMusicProfileCreated", { enumerable: true, get: function () { return recommendations_1.onUserMusicProfileCreated; } });
Object.defineProperty(exports, "onUserMusicProfileChanged", { enumerable: true, get: function () { return recommendations_1.onUserMusicProfileChanged; } });
var friendships_1 = require("./friendships");
Object.defineProperty(exports, "acceptFriendRequest", { enumerable: true, get: function () { return friendships_1.acceptFriendRequest; } });
Object.defineProperty(exports, "onFriendRequest", { enumerable: true, get: function () { return friendships_1.onFriendRequest; } });
Object.defineProperty(exports, "onFriendRequestAccepted", { enumerable: true, get: function () { return friendships_1.onFriendRequestAccepted; } });
Object.defineProperty(exports, "onFriendRequestDeleted", { enumerable: true, get: function () { return friendships_1.onFriendRequestDeleted; } });
var chat_1 = require("./chat");
Object.defineProperty(exports, "onNewMessage", { enumerable: true, get: function () { return chat_1.onNewMessage; } });
Object.defineProperty(exports, "onChatSoftDeleted", { enumerable: true, get: function () { return chat_1.onChatSoftDeleted; } });
Object.defineProperty(exports, "onChatMessageDeleted", { enumerable: true, get: function () { return chat_1.onChatMessageDeleted; } });
var daily_song_1 = require("./daily_song");
Object.defineProperty(exports, "expireDailySongs", { enumerable: true, get: function () { return daily_song_1.expireDailySongs; } });
//# sourceMappingURL=index.js.map