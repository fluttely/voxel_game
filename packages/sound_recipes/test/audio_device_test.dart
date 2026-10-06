import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recipes/sound_recipes.dart';

/// A device that writes down every open and close, each open answered by
/// the next of [opens] (an open with none left answers true at once).
class _Fake {
  _Fake([List<Completer<bool>>? opens]) : _opens = opens ?? [];

  final List<Completer<bool>> _opens;
  final List<String> log = [];

  late final AudioDevice device = AudioDevice(
    open: () {
      log.add('open');
      return _opens.isEmpty ? Future.value(true) : _opens.removeAt(0).future;
    },
    close: () async => log.add('close'),
  );
}

void main() {
  final real = AudioDevice.instance;
  tearDown(() => AudioDevice.instance = real);

  test('a release while the open is in flight never closes the device under the next holder', () async {
    final opening = Completer<bool>();
    final fake = _Fake([opening]);
    final first = fake.device.acquire();
    final firstGone = fake.device.release();
    final second = fake.device.acquire();
    opening.complete(true);
    expect(await first, isTrue);
    await firstGone;
    expect(await second, isTrue);
    expect(fake.log, ['open', 'close', 'open'], reason: 'the second open comes after the close');
    expect(fake.device.isOpen, isTrue);
    expect(fake.device.held, 1);
  });

  test('a second holder, queued behind an open in flight, shares it; the last release closes once', () async {
    final opening = Completer<bool>();
    final fake = _Fake([opening]);
    final first = fake.device.acquire();
    final second = fake.device.acquire();
    opening.complete(true);
    expect([await first, await second], [true, true]);
    await fake.device.release();
    expect(fake.log, ['open'], reason: 'one holder is left');
    await fake.device.release();
    expect(fake.log, ['open', 'close']);
    expect(fake.device.isOpen, isFalse);
    await expectLater(fake.device.release(), throwsStateError);
    expect(await fake.device.acquire(), isTrue, reason: 'the queue goes on past an error');
  });

  test('two banks share one open, and the device closes when both are gone', () async {
    final fake = _Fake();
    AudioDevice.instance = fake.device;
    final a = SoundBank(recipes: const {});
    final b = SoundBank(recipes: const {});
    expect([await a.init(), await b.init()], [true, true]);
    expect([a.ready, b.ready], [true, true]);
    expect(fake.device.held, 2);
    a.dispose();
    await pumpEventQueue();
    expect(fake.log, ['open']);
    b.dispose();
    await pumpEventQueue();
    expect(fake.log, ['open', 'close']);
    a.dispose();
    await pumpEventQueue();
    expect(fake.log, ['open', 'close'], reason: 'a bank lets go once');
  });

  test('a failed open leaves the bank silent, holding nothing', () async {
    final fake = _Fake([Completer<bool>()..complete(false)]);
    AudioDevice.instance = fake.device;
    final bank = SoundBank(recipes: const {});
    expect(await bank.init(), isFalse);
    expect(bank.ready, isFalse);
    expect(fake.device.held, 0);
    bank
      ..play('anything')
      ..dispose();
    await pumpEventQueue();
    expect(fake.log, ['open'], reason: 'nothing was held, so nothing closes');
  });
}
