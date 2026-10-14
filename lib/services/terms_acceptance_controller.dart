import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:musi_link/utils/retry_backoff.dart';

/// Aceptación de los términos vigentes por la cuenta de la sesión actual.
///
/// Restaura la aceptación cacheada, la verifica en el servidor en segundo
/// plano y registra las aceptaciones nuevas de forma optimista. Descarta las
/// respuestas que llegan después de cambiar de sesión.
class TermsAcceptanceController extends ChangeNotifier {
  TermsAcceptanceController({
    required this._auth,
    this.acceptanceRequired = true,
    this._readCachedAcceptance,
    this._refreshAcceptance,
    this._submitAcceptance,
  }) {
    final uid = _auth.currentUser?.uid;
    if (uid != null) _restoreAcceptance(uid);
  }

  final FirebaseAuth _auth;
  final bool acceptanceRequired;
  final bool Function(String uid)? _readCachedAcceptance;
  final Future<bool> Function(String uid)? _refreshAcceptance;

  /// Registra la aceptación en el servidor. Devuelve false ante un rechazo
  /// definitivo y lanza una excepción si conviene reintentar.
  final Future<bool> Function(String uid)? _submitAcceptance;

  String? _acceptedUid;
  String? _checkedUid;
  int _authGeneration = 0;
  int _revision = 0;
  Timer? _refreshTimer;
  final _refreshBackoff = RetryBackoff();
  String? _submittingUid;
  int _submission = 0;
  Timer? _submitTimer;
  final _submitBackoff = RetryBackoff();
  String? _saveFailedUid;

  bool get termsAccepted {
    if (!acceptanceRequired) return true;
    final uid = _auth.currentUser?.uid;
    return uid != null && _acceptedUid == uid;
  }

  /// La falta de caché no bloquea el arranque. Solo una respuesta negativa
  /// del servidor exige abrir el diálogo de aceptación.
  bool get termsCheckPending {
    final uid = _auth.currentUser?.uid;
    return _refreshAcceptance != null && uid != null && _checkedUid != uid;
  }

  bool get mustAcceptTerms => !termsAccepted && !termsCheckPending;

  /// Aplica un cambio de sesión sin avisar a los listeners: quien coordina la
  /// sesión avisa una sola vez tras actualizar también el alta.
  void handleAuthChange(User? user) {
    final generation = ++_authGeneration;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshBackoff.reset();
    if (_checkedUid != user?.uid) _checkedUid = null;
    if (_submittingUid != user?.uid) _cancelSubmission();
    if (user == null) {
      _acceptedUid = null;
      _checkedUid = null;
      return;
    }
    _restoreAcceptance(user.uid);
    if (acceptanceRequired) unawaited(_refresh(user, generation));
  }

  /// Acepta de forma optimista: el router avanza al instante y el registro en
  /// el servidor se confirma en segundo plano. Si el servidor lo rechaza, se
  /// vuelve a exigir la aceptación.
  void acceptTerms(String uid) {
    if (_auth.currentUser?.uid != uid || _submittingUid == uid) return;
    if (_submitAcceptance != null) {
      _submittingUid = uid;
      _submitBackoff.reset();
      _saveFailedUid = null;
      unawaited(_submit(uid, ++_submission));
    }
    setTermsAccepted(uid);
  }

  /// Indica, una sola vez, que el último registro de aceptación fue rechazado.
  bool takeTermsSaveError() {
    final failedUid = _saveFailedUid;
    _saveFailedUid = null;
    return failedUid != null && failedUid == _auth.currentUser?.uid;
  }

  void setTermsAccepted(String uid) {
    if (_auth.currentUser?.uid != uid) return;
    _revision++;
    _acceptedUid = uid;
    _checkedUid = uid;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    notifyListeners();
  }

  void _restoreAcceptance(String uid) {
    if (_acceptedUid == uid) return;
    _acceptedUid = _readCachedAcceptance?.call(uid) == true ? uid : null;
  }

  Future<void> _refresh(User user, int generation) async {
    final refresh = _refreshAcceptance;
    if (refresh == null) return;
    final revision = _revision;
    try {
      final accepted = await refresh(user.uid);
      if (!_isCurrentAuthUser(user, generation) || revision != _revision) {
        return;
      }
      // El servidor aún no refleja una aceptación que se está registrando.
      if (!accepted && _submittingUid == user.uid) return;
      _acceptedUid = accepted ? user.uid : null;
      _checkedUid = user.uid;
      _refreshBackoff.reset();
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthUser(user, generation) || revision != _revision) {
        return;
      }
      // El estado desconocido permanece en segundo plano incluso sin caché.
      _refreshTimer = Timer(_refreshBackoff.next(), () {
        _refreshTimer = null;
        if (_isCurrentAuthUser(user, generation)) {
          unawaited(_refresh(user, generation));
        }
      });
    }
  }

  Future<void> _submit(String uid, int submission) async {
    final submit = _submitAcceptance;
    if (submit == null || !_isCurrentSubmission(uid, submission)) return;
    final bool confirmed;
    try {
      confirmed = await submit(uid);
    } catch (_) {
      if (!_isCurrentSubmission(uid, submission)) return;
      // Sin respuesta del servidor la aceptación sigue pendiente de registro.
      _submitTimer = Timer(_submitBackoff.next(), () {
        _submitTimer = null;
        unawaited(_submit(uid, submission));
      });
      return;
    }
    if (!_isCurrentSubmission(uid, submission)) return;
    _submittingUid = null;
    // Descarta cualquier lectura iniciada antes de conocer el resultado.
    _revision++;
    if (confirmed) return;
    _acceptedUid = null;
    _saveFailedUid = uid;
    notifyListeners();
  }

  bool _isCurrentAuthUser(User user, int generation) =>
      generation == _authGeneration && _auth.currentUser?.uid == user.uid;

  bool _isCurrentSubmission(String uid, int submission) =>
      submission == _submission && _auth.currentUser?.uid == uid;

  void _cancelSubmission() {
    _submission++;
    _submittingUid = null;
    _submitTimer?.cancel();
    _submitTimer = null;
  }

  @override
  void dispose() {
    _authGeneration++;
    _refreshTimer?.cancel();
    _cancelSubmission();
    super.dispose();
  }
}
