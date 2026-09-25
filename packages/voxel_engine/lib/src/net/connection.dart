import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A message: a JSON object whose `t` names its type.
typedef NetMessage = Map<String, Object?>;

/// One end of a TCP connection carrying [NetMessage]s, one JSON object a
/// line. TCP is a stream, so a message of any size arrives whole and in
/// order.
class NetConnection {
  /// A connection over [socket].
  NetConnection(this.socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isEmpty) return;
            final decoded = jsonDecode(line);
            if (decoded is! Map<String, Object?>) throw FormatException('a message is a JSON object', line);
            final h = _handler;
            if (h == null) {
              _buffer.add(decoded);
            } else {
              h(decoded);
            }
          },
          onError: (Object e) => _close(),
          onDone: _close,
          cancelOnError: true,
        );
  }

  /// The socket.
  final Socket socket;

  late final StreamSubscription<String> _sub;
  final Completer<void> _done = Completer<void>();
  void Function(NetMessage message)? _handler;
  final List<NetMessage> _buffer = [];

  /// Hands every message, in order, to [handler] from now on, the ones that
  /// arrived while no handler was set first. A later call replaces it; null
  /// holds the messages until the next handler.
  void listen(void Function(NetMessage message)? handler) {
    _handler = handler;
    if (handler == null) return;
    while (_buffer.isNotEmpty && identical(_handler, handler)) {
      handler(_buffer.removeAt(0));
    }
  }

  /// The next message: waits for it, and holds the ones after it for the
  /// next [listen].
  Future<NetMessage> next() {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    final c = Completer<NetMessage>();
    _handler = (m) {
      _handler = null;
      c.complete(m);
    };
    return c.future;
  }

  /// Completes when the connection closes, from either end.
  Future<void> get done => _done.future;

  /// Whether the connection is closed.
  bool get isClosed => _done.isCompleted;

  /// Sends [message] (of type `message['t']`).
  void send(NetMessage message) {
    if (isClosed) return;
    socket.writeln(jsonEncode(message));
  }

  void _close() {
    if (_done.isCompleted) return;
    _done.complete();
  }

  /// Closes the connection.
  Future<void> close() async {
    await _sub.cancel();
    await socket.close();
    socket.destroy();
    _close();
  }
}
