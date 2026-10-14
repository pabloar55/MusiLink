import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/services/chat_notification_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatNotificationEntry _entry(String text, {String? senderId = 'ana'}) => (
  senderName: 'Ana',
  senderId: senderId,
  text: text,
  sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
);

void main() {
  late SharedPreferences prefs;
  late ChatNotificationHistory history;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    history = ChatNotificationHistory(prefs);
  });

  test('conserva solo los últimos mensajes de cada chat', () async {
    for (var i = 1; i <= ChatNotificationHistory.maxMessagesPerChat; i++) {
      await history.append('chat', _entry('m$i'));
    }
    await history.append('other', _entry('otro'));

    final messages = await history.append('chat', _entry('nuevo'));

    expect(messages.map((message) => message.text), [
      'm2',
      'm3',
      'm4',
      'm5',
      'nuevo',
    ]);
    expect(messages.last, _entry('nuevo'));
    expect(
      (await history.append('other', _entry('segundo'))).map((m) => m.text),
      ['otro', 'segundo'],
    );
  });

  test('lee el historial guardado por versiones anteriores', () async {
    // Formato persistido que también escribe el isolate de segundo plano.
    SharedPreferences.setMockInitialValues({
      'chat_notification_history': jsonEncode({
        'chat': [
          {'senderName': 'Luis', 'text': 'hola', 'timestamp': 500},
        ],
      }),
    });
    prefs = await SharedPreferences.getInstance();
    history = ChatNotificationHistory(prefs);

    final messages = await history.append('chat', _entry('adiós'));

    expect(messages.first, (
      senderName: 'Luis',
      senderId: null,
      text: 'hola',
      sentAt: DateTime.fromMillisecondsSinceEpoch(500),
    ));
    final stored = jsonDecode(
      prefs.getString('chat_notification_history')!,
    ) as Map<String, dynamic>;
    expect(stored['chat'], [
      {'senderName': 'Luis', 'text': 'hola', 'timestamp': 500},
      {
        'senderName': 'Ana',
        'senderId': 'ana',
        'text': 'adiós',
        'timestamp': 1000,
      },
    ]);
  });

  test('retira un chat sin tocar los demás y vacía al cerrar sesión', () async {
    await history.remove('chat');
    expect(prefs.getString('chat_notification_history'), isNull);

    await history.append('chat', _entry('uno'));
    await history.append('other', _entry('dos', senderId: null));
    await history.remove('chat');

    expect((await history.append('chat', _entry('tres'))).map((m) => m.text), [
      'tres',
    ]);
    expect(
      (await history.append('other', _entry('cuatro'))).map((m) => m.text),
      ['dos', 'cuatro'],
    );

    await history.clear();
    expect(prefs.getString('chat_notification_history'), isNull);
  });
}
