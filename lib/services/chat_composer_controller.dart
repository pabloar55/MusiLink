import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController, TextSelection;
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/chat_service.dart';

/// Borrador de un chat —texto y cita a la que responde— y su envío.
///
/// Cada pantalla crea el suyo, igual que su historial. Avisa a sus listeners
/// cuando cambia la cita; el texto se escucha en [textController].
class ChatComposerController extends ChangeNotifier {
  ChatComposerController({
    required this._service,
    required this._chatId,
    required this._onSent,
    required this._onError,
  });

  final ChatService _service;
  final String _chatId;

  /// Llega cuando el servicio acepta un envío.
  final void Function() _onSent;

  /// Avisa de un envío fallido, con su borrador ya restaurado.
  final void Function(Object error) _onError;

  final textController = TextEditingController();

  Message? _replyingTo;
  bool _disposed = false;

  /// Mensaje al que responderá el próximo envío.
  Message? get replyingTo => _replyingTo;

  void startReply(Message message) {
    _replyingTo = message;
    notifyListeners();
  }

  void cancelReply() {
    _replyingTo = null;
    notifyListeners();
  }

  /// Envía el texto en redacción junto a su cita; uno vacío no se envía.
  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;

    final replyTo = _takeReply();
    textController.clear();
    await _send(
      () => _service.sendMessage(_chatId, text, replyTo: replyTo),
      replyTo,
      text: text,
    );
  }

  /// Envía una canción como respuesta a la cita en curso.
  Future<void> sendTrack(Track track) async {
    // La canción no consume el texto que hubiera a medio escribir.
    final remaining = textController.text;
    final replyTo = _takeReply();
    await _send(
      () => _service.sendTrackMessage(_chatId, track, replyTo: replyTo),
      replyTo,
      remaining: remaining,
    );
  }

  Future<void> _send(
    Future<void> Function() request,
    Message? replyTo, {
    String? text,
    String remaining = '',
  }) async {
    try {
      await request();
    } catch (error) {
      if (_disposed) return;
      _restore(replyTo, text: text, remaining: remaining);
      _onError(error);
      return;
    }
    if (!_disposed) _onSent();
  }

  /// La respuesta en curso se consume con el mensaje que la envía.
  Message? _takeReply() {
    final replyTo = _replyingTo;
    if (replyTo != null) cancelReply();
    return replyTo;
  }

  /// Un envío fallido devuelve su texto y su cita juntos, y solo si el
  /// borrador sigue como quedó al enviar ([remaining]): un error tardío no
  /// se mezcla con el texto o la cita de un borrador posterior.
  void _restore(Message? replyTo, {String? text, String remaining = ''}) {
    if (_replyingTo != null || textController.text != remaining) return;
    if (text != null) {
      textController.text = text;
      textController.selection = TextSelection.collapsed(offset: text.length);
    }
    if (replyTo != null) startReply(replyTo);
  }

  @override
  void dispose() {
    _disposed = true;
    textController.dispose();
    super.dispose();
  }
}
