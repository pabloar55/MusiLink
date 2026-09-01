// Keep this file as the public Firebase Functions manifest. Domain logic lives
// in focused modules so importing one feature does not expose unrelated code.
export { searchSpotifyArtists, searchSpotifyTracks } from './spotify';
export { getSimilarArtists } from './lastfm';
export { requestAccountDeletion, processAccountDeletion } from './account_deletion';
export { createUserProfile } from './user_profile';
export { saveMusicProfile } from './music_profile_write';
export {
  onUserMusicProfileCreated,
  onUserMusicProfileChanged,
} from './recommendations';
export {
  acceptFriendRequest,
  onFriendRequest,
  onFriendRequestAccepted,
  onFriendRequestDeleted,
} from './friendships';
export {
  onNewMessage,
  onChatSoftDeleted,
  onChatMessageDeleted,
} from './chat';
export { sendChatMessage, sendFriendRequest } from './social_writes';
export { expireDailySongs } from './daily_song';
