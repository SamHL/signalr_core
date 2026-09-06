import 'dart:async';

import 'package:signalr_core/signalr_core.dart';
import 'package:test/test.dart';

/// Records what it was asked to send and never fails, so the queue's own
/// behaviour is what the tests observe.
class _FakeTransport implements Transport {
  final List<dynamic> sent = [];

  @override
  OnReceive? onreceive;

  @override
  OnClose? onclose;

  @override
  Future<void> connect(String? url, TransferFormat? transferFormat) async {}

  @override
  Future<void> send(dynamic data) async {
    sent.add(data);
  }

  @override
  Future<void> stop() async {}
}

/// Queues [data] and swallows the rejection the queue raises for anything
/// still outstanding when it stops, which is expected and not what is under
/// test here.
void sendIgnoringOutcome(TransportSendQueue queue, dynamic data) {
  queue.send(data).catchError((Object _) {});
}

void main() {
  group('TransportSendQueue.stop', () {
    test('does not throw when a send has already woken the send loop',
        () async {
      final queue = TransportSendQueue(transport: _FakeTransport());

      // send() buffers synchronously, which completes the same completer that
      // stop() used to complete unconditionally. Calling stop() before the
      // send loop resumes is the race that threw StateError, and because that
      // throw was synchronous on the socket onclose path nothing caught it.
      sendIgnoringOutcome(queue, 'hello');

      expect(() => queue.stop(), returnsNormally);
      await queue.stop();
    });

    test('is safe to call twice', () async {
      final queue = TransportSendQueue(transport: _FakeTransport());

      // The queue rejects whatever is outstanding when it stops, so give that
      // rejection a listener first. Stopping a queue nobody ever sent on
      // leaves that rejection unhandled, which is a separate pre-existing
      // wart in this package and not what this test is about.
      sendIgnoringOutcome(queue, 'hello');

      // An abnormal websocket close used to run the whole close path twice, so
      // the second stop() always landed on an already completed completer.
      await queue.stop();
      expect(() => queue.stop(), returnsNormally);
    });

    test('stopping before any send raises no unhandled rejection', () async {
      // The constructor used to seed _transportResult, so a queue stopped
      // before anything was sent had sendLoop reject a completer nobody was
      // waiting on. That reached the zone as a fatal unhandled error. The
      // background teardown we now do on every app pause makes stopping a
      // freshly started connection routine, so this path matters.
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final queue = TransportSendQueue(transport: _FakeTransport());
        await queue.stop();
        // Let any rejection reach the zone before asserting.
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) {
        errors.add(error);
      });

      expect(errors, isEmpty);
    });

    test('still stops a queue that is idle', () async {
      final transport = _FakeTransport();
      final queue = TransportSendQueue(transport: transport);

      await queue.stop();

      // The loop has broken, so a later send is never handed to the transport.
      sendIgnoringOutcome(queue, 'ignored');
      await Future<void>.delayed(Duration.zero);
      expect(transport.sent, isEmpty);
    });
  });
}
