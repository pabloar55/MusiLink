import 'package:firebase_core/firebase_core.dart';

/// El backend rechazó la operación por superar su límite de peticiones.
class RateLimitedException implements Exception {
  const RateLimitedException(this.cause);

  final Object cause;
}

/// El backend rechazó la operación porque el usuario no tiene permiso.
class NotAllowedException implements Exception {
  const NotAllowedException(this.cause);

  final Object cause;
}

/// Traduce los rechazos del backend que la interfaz distingue para que las
/// pantallas no dependan de Firebase. Cualquier otro error se devuelve tal
/// cual.
Object toServiceException(Object error) {
  if (error is! FirebaseException) return error;
  return switch (error.code) {
    'resource-exhausted' => RateLimitedException(error),
    'permission-denied' => NotAllowedException(error),
    _ => error,
  };
}
