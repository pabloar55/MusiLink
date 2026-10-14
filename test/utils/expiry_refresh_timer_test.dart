import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/expiry_refresh_timer.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 12);
  late int expirations;
  late ExpiryRefreshTimer timer;

  setUp(() {
    expirations = 0;
    timer = ExpiryRefreshTimer(() => expirations++);
  });

  tearDown(() => timer.cancel());

  testWidgets('avisa en la caducidad futura más próxima', (tester) async {
    timer.schedule([
      now.add(const Duration(minutes: 5)),
      null,
      now.subtract(const Duration(minutes: 1)),
      now.add(const Duration(minutes: 2)),
    ], now: now);

    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(expirations, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(expirations, 1);
  });

  testWidgets('no reinicia el temporizador si la caducidad no cambia', (
    tester,
  ) async {
    final expiry = now.add(const Duration(minutes: 2));
    timer.schedule([expiry], now: now);
    await tester.pump(const Duration(minutes: 1));
    // Una reconstrucción posterior no debe retrasar el aviso.
    timer.schedule([expiry], now: now);

    await tester.pump(const Duration(minutes: 1));
    expect(expirations, 1);
  });

  testWidgets('reprograma al cambiar la caducidad y tras avisar', (
    tester,
  ) async {
    timer.schedule([now.add(const Duration(minutes: 2))], now: now);
    timer.schedule([now.add(const Duration(minutes: 5))], now: now);
    await tester.pump(const Duration(minutes: 2));
    expect(expirations, 0);
    await tester.pump(const Duration(minutes: 3));
    expect(expirations, 1);

    // Tras avisar, la misma caducidad vuelve a programarse si sigue vigente.
    final later = now.add(const Duration(minutes: 5));
    timer.schedule([later.add(const Duration(minutes: 1))], now: later);
    await tester.pump(const Duration(minutes: 1));
    expect(expirations, 2);
  });

  testWidgets('sin caducidades futuras ni tras cancelar no avisa', (
    tester,
  ) async {
    timer.schedule([now.subtract(const Duration(seconds: 1)), null], now: now);
    timer.schedule([now.add(const Duration(minutes: 1))], now: now);
    timer.cancel();

    await tester.pump(const Duration(minutes: 2));
    expect(expirations, 0);
  });
}
