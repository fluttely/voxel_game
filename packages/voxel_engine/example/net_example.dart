// A host and a client in one process, over localhost: the client joins and
// sends where it stands, the host tells everyone, then the client leaves.
//
//   dart run example/net_example.dart
import 'dart:async';

import 'package:voxel_engine/net.dart';

Future<void> main() async {
  // 1. The host listens (port 0 picks a free one; a game uses 7777).
  final host = await NetHost.bind(port: 0);
  final left = Completer<void>();
  host
    ..onJoin = ((peer) => print('host: player ${peer.id} joined'))
    ..onMessage = ((peer, message) {
      print('host: player ${peer.id} says $message');
      // The host is the authority: it answers and tells every player.
      if (message['t'] == 'pose') host.broadcast({'t': 'moved', 'id': peer.id, 'p': message['p']});
    })
    ..onLeave = ((peer) {
      print('host: player ${peer.id} left');
      left.complete();
    });

  // 2. A client connects. On another machine, pass the host's address.
  final client = await connectToHost('127.0.0.1', port: host.port);

  // 3. Messages are JSON objects; `t` names their type.
  client.send({'t': 'pose', 'p': [12.5, 64.0, -3.0]});
  final reply = await client.next();
  print('client: heard ${reply['t']} of player ${reply['id']} at ${reply['p']}');

  // 4. Or hand every message to a listener, in order.
  client.listen((message) => print('client: ${message['t']}'));
  host.broadcast({'t': 'time', 'day': 0.25});
  await Future<void>.delayed(const Duration(milliseconds: 100));

  // 5. Leaving is noticed on the other side.
  await client.close();
  await left.future;
  await host.close();
}
