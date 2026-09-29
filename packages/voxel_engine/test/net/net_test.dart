import 'dart:async';

import 'package:test/test.dart';
import 'package:voxel_engine/net.dart';

void main() {
  test('a client joins, both sides talk, a broadcast reaches it, and leaving is noticed', () async {
    final host = await NetHost.bind(port: 0);
    final joined = Completer<NetPeer>();
    final heard = StreamController<NetMessage>();
    final left = Completer<int>();
    host
      ..onJoin = joined.complete
      ..onMessage = ((NetPeer peer, NetMessage m) => heard.add(m))
      ..onLeave = ((NetPeer peer) => left.complete(peer.id));
    final client = await connectToHost('127.0.0.1', port: host.port);
    final peer = await joined.future;
    expect(peer.id, 2);
    client.send({
      't': 'pose',
      'p': [1.5, 2, -3],
    });
    final m = await heard.stream.first;
    expect(m['t'], 'pose');
    expect(m['p'], [1.5, 2, -3]);
    final got = client.next();
    host.broadcast({'t': 'state', 'big': List.filled(5000, 7)});
    host.broadcast({'t': 'after'});
    final s = await got;
    expect((s['big']! as List<Object?>).length, 5000, reason: 'a large message arrives whole');
    final later = <String>[];
    await Future<void>.delayed(const Duration(milliseconds: 100));
    client.listen((m) => later.add(m['t']! as String));
    expect(later, ['after'], reason: 'held while nobody listened, then handed over in order');
    await client.close();
    expect(await left.future.timeout(const Duration(seconds: 5)), 2);
    await peer.connection.socket.done.timeout(const Duration(seconds: 5));
    expect(peer.connection.isClosed, isTrue, reason: "the host releases a leaver's socket");
    await host.close();
  });

  test('a broadcast is encoded once and reaches every peer but the one excepted, whole', () async {
    final host = await NetHost.bind(port: 0);
    final joined = StreamController<NetPeer>();
    host.onJoin = joined.add;
    final peersJoined = StreamIterator(joined.stream);
    final a = await connectToHost('127.0.0.1', port: host.port);
    await peersJoined.moveNext();
    final b = await connectToHost('127.0.0.1', port: host.port);
    await peersJoined.moveNext();
    final bId = peersJoined.current.id;
    final big = {'t': 'state', 'big': List.generate(20000, (i) => i)};
    final gotA = a.next(), gotB = b.next();
    host.broadcast(big);
    for (final m in [await gotA, await gotB]) {
      expect(m, big, reason: 'the one encoding arrives whole at both');
    }
    final onlyA = a.next();
    host.broadcast({'t': 'not-b'}, except: bId);
    host.broadcast({'t': 'all'});
    expect((await onlyA)['t'], 'not-b');
    expect((await b.next())['t'], 'all', reason: 'the excepted peer skips it and gets the next');
    final encoded = EncodedMessage({'t': 'x', 'n': 1});
    for (final p in host.peers.values) {
      p.connection.sendEncoded(encoded);
    }
    expect(await a.next(), {'t': 'all'});
    expect(await a.next(), {'t': 'x', 'n': 1});
    expect(await b.next(), {'t': 'x', 'n': 1});
    await a.close();
    await b.close();
    await host.close();
  });

  test('a peer that hangs up mid-broadcast closes its connection, not the process', () async {
    final host = await NetHost.bind(port: 0);
    final joined = Completer<NetPeer>();
    final left = Completer<int>();
    host
      ..onJoin = joined.complete
      ..onLeave = ((NetPeer peer) => left.complete(peer.id));
    final client = await connectToHost('127.0.0.1', port: host.port);
    final peer = await joined.future;
    client.socket.destroy();
    final big = EncodedMessage({'t': 'state', 'big': List.filled(200000, 7)});
    for (var i = 0; i < 20; i++) {
      peer.connection.sendEncoded(big);
    }
    expect(await left.future.timeout(const Duration(seconds: 5)), 2);
    expect(peer.connection.isClosed, isTrue);
    await host.close();
  });
}
