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
}
