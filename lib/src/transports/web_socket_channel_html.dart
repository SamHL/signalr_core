import 'package:http/http.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens [uri] and waits for the browser to finish the handshake.
///
/// [WebSocketChannel.connect] returns before the socket is open and reports a
/// failed handshake only through [WebSocketChannel.ready]. Returning the
/// channel without awaiting it made a refused connection look like a
/// successful one, and left ready's rejection with no listener, where it
/// escaped as an unhandled "WebSocketChannelException: Failed to connect
/// WebSocket". Awaiting it here makes the failure a thrown error from
/// connect, which HttpConnection already catches to try the next transport.
Future<WebSocketChannel> connect(Uri uri, {BaseClient? client}) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready;
  return channel;
}
