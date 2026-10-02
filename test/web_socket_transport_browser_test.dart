@TestOn('browser')
library;

import 'package:http/browser_client.dart';
import 'package:signalr_core/signalr_core.dart';
import 'package:signalr_core/src/transports/web_socket_transport.dart';
import 'package:test/test.dart';

/// A WebSocket server on the VM that echoes what it receives, so the browser
/// test has something to connect to. It sends back the port it listens on.
const _echoServer = r'''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen(socket.add);
  });
  channel.sink.add(server.port);
}
''';

void main() {
  test('a WebSocket that connects reports success and carries messages',
      () async {
    final server = spawnHybridCode(_echoServer);
    final port = await server.stream.first as int;
    final received = <dynamic>[];
    final transport = WebSocketTransport(
      client: BrowserClient(),
      logging: (_, __) {},
      logMessageContent: false,
    )..onreceive = received.add;

    await transport.connect('http://127.0.0.1:$port/hub', TransferFormat.text);
    await transport.send('ping');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(received, ['ping']);
    await transport.stop();
  });

  test('a WebSocket that cannot connect fails connect, and nothing else',
      () async {
    // Nothing listens on port 1, so the browser refuses the handshake. The
    // channel reports that through its ready future; before the fix nobody
    // awaited it, connect claimed success, and the rejected future escaped
    // as an unhandled WebSocketChannelException, which fails this test.
    final closes = <Exception?>[];
    final transport = WebSocketTransport(
      client: BrowserClient(),
      logging: (_, __) {},
      logMessageContent: false,
    )..onclose = closes.add;

    await expectLater(
      transport.connect('http://127.0.0.1:1/hub', TransferFormat.text),
      throwsA(anything),
    );

    // A transport that never opened must not report a close either, or the
    // connection would treat the failure as an open socket going away.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(closes, isEmpty);
  });
}
