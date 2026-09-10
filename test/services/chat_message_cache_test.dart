import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/chat_message_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late ChatMessageCache cache;
  final time = DateTime(2026, 9, 6, 12, 0, 0, 0, 123);
  final message = Message(
    id: 'message-id',
    senderId: 'sender',
    text: 'Song',
    timestamp: time,
    read: true,
    delivered: true,
    type: MessageType.track,
    trackData: const Track(
      title: 'Title',
      artist: 'Artist',
      imageUrl: 'cover',
      spotifyUrl: 'track',
    ),
    reactions: const {
      '❤️': ['alice', 'bob'],
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    cache = ChatMessageCache(prefs);
  });

  test(
    'restores full messages and deletion boundary in a new instance',
    () async {
      final since = time.subtract(const Duration(days: 1));
      cache.write('alice', 'chat', (since: since, messages: [message]));
      await Future<void>.delayed(Duration.zero);
      await prefs.reload();
      final restored = ChatMessageCache(prefs).read('alice', 'chat')!;
      expect(restored.since, since);
      final actual = restored.messages.single;
      expect(actual.id, message.id);
      expect(actual.senderId, message.senderId);
      expect(actual.timestamp, time);
      expect(actual.text, message.text);
      expect(actual.read, isTrue);
      expect(actual.delivered, isTrue);
      expect(actual.type, MessageType.track);
      expect(actual.trackData!.toMap(), message.trackData!.toMap());
      expect(actual.reactions, message.reactions);
    },
  );

  test('isolates accounts including identifiers containing separators', () {
    cache.write('alice.chat.bob', 'c', (since: null, messages: [message]));
    final restored = ChatMessageCache(prefs);
    expect(restored.read('alice', 'bob.chat.c'), isNull);
    expect(restored.read('bob', 'c'), isNull);
    expect(restored.read('alice.chat.bob', 'c')!.messages, hasLength(1));
  });

  test('keeps an empty chat distinct from a cache miss and filters deleted messages', () {
    cache.write('alice', 'chat', (since: time, messages: [message]));
    final restored = ChatMessageCache(prefs);
    expect(restored.read('alice', 'chat')!.messages, isEmpty);
    expect(restored.read('alice', 'unknown'), isNull);
  });

  test('retains only the latest page and twenty recently updated chats', () {
    final messages = List.generate(
      40,
      (i) => Message(
        id: '$i',
        senderId: 'alice',
        text: '$i',
        timestamp: time.add(Duration(minutes: i)),
      ),
    );
    for (var i = 0; i < 21; i++) {
      cache.write('alice', 'chat-$i', (since: null, messages: messages));
    }
    final restored = ChatMessageCache(prefs);
    expect(restored.read('alice', 'chat-0'), isNull);
    expect(restored.read('alice', 'chat-20')!.messages, hasLength(30));
    expect(restored.read('alice', 'chat-20')!.messages.first.id, '10');
  });

  test(
    'deletion and logout persist without clearing unrelated preferences',
    () async {
      await prefs.setString('theme_mode', 'dark');
      cache.write('alice', 'chat', (since: null, messages: [message]));
      cache.write('bob', 'chat', (since: null, messages: [message]));
      cache.remove('alice', 'chat');
      expect(ChatMessageCache(prefs).read('alice', 'chat'), isNull);
      expect(ChatMessageCache(prefs).read('bob', 'chat'), isNotNull);
      cache.clear();
      await Future<void>.delayed(Duration.zero);
      await prefs.reload();
      expect(ChatMessageCache(prefs).read('bob', 'chat'), isNull);
      expect(prefs.getString('theme_mode'), 'dark');
    },
  );

  test('ignores corrupted data without losing other chats', () async {
    cache.write('alice', 'chat', (since: null, messages: [message]));
    cache.write('alice', 'other', (since: null, messages: [message]));
    final key = prefs.getKeys().singleWhere(
      (key) => key.endsWith('.chat.chat'),
    );
    await prefs.setString(key, '{broken');
    final restored = ChatMessageCache(prefs);
    expect(restored.read('alice', 'chat'), isNull);
    expect(restored.read('alice', 'other'), isNotNull);
  });
}
