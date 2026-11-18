import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mads/network/doh_http_client.dart';

const _host = 'project.supabase.co';

String _answer(List<Map<String, Object>> entries) =>
    jsonEncode({'Status': 0, 'Answer': entries});

/// A fake client that records calls and replies with [handler].
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    return handler(request);
  }
}

http.StreamedResponse _ok(String body, [int status = 200]) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status);

void main() {
  group('DohResolver', () {
    test('keeps only usable IPv4 answers and the smallest TTL', () {
      final (addresses, ttl) = DohResolver.parseAnswer(
        _answer([
          {'type': 5, 'data': 'alias.example.', 'TTL': 10}, // CNAME
          {'type': 1, 'data': '104.18.38.10', 'TTL': 120},
          {'type': 1, 'data': '172.64.149.246', 'TTL': 60},
          {'type': 1, 'data': '127.0.0.1', 'TTL': 5}, // loopback
          {'type': 1, 'data': '0.0.0.0', 'TTL': 5},
          {'type': 28, 'data': '2606:4700::1', 'TTL': 5}, // IPv6
        ]),
      );
      expect(addresses.map((a) => a.address), ['104.18.38.10', '172.64.149.246']);
      expect(ttl, 60);
    });

    test('tries the next service when the first fails, then caches', () async {
      final asked = <String>[];
      var now = DateTime(2026, 11, 18, 12);
      final resolver = DohResolver(
        endpoints: [Uri.parse('https://one.test/q'), Uri.parse('https://two.test/q')],
        now: () => now,
        fetch: (url) async {
          asked.add(url.host);
          if (url.host == 'one.test') throw const SocketException('blocked');
          expect(url.queryParameters, {'name': _host, 'type': 'A'});
          return _answer([
            {'type': 1, 'data': '104.18.38.10', 'TTL': 100},
          ]);
        },
      );
      expect((await resolver.resolve(_host)).single.address, '104.18.38.10');
      expect(asked, ['one.test', 'two.test']);
      await resolver.resolve(_host.toUpperCase()); // cached, any case
      expect(asked.length, 2);
      now = now.add(const Duration(seconds: 101)); // past the TTL
      await resolver.resolve(_host);
      expect(asked.length, 4);
    });

    test('throws a SocketException when no service answers', () async {
      final resolver = DohResolver(
        endpoints: [Uri.parse('https://one.test/q')],
        fetch: (_) async => _answer([]),
      );
      expect(resolver.resolve(_host), throwsA(isA<SocketException>()));
    });
  });

  group('DohFallbackClient', () {
    DohFallbackClient make(_FakeClient primary, _FakeClient fallback,
        {DateTime Function()? now}) =>
        DohFallbackClient(
          hosts: {_host},
          primary: primary,
          fallback: fallback,
          now: now,
        );

    final url = Uri.parse('https://$_host/auth/v1/signup');

    test('retries through the fallback after a handshake error', () async {
      final primary = _FakeClient((_) => throw const HandshakeException('bad'));
      final fallback = _FakeClient((_) async => _ok('{"ok":true}'));
      final client = make(primary, fallback);
      final response = await client.post(url, body: '{"email":"a@b.c"}');
      expect(response.statusCode, 200);
      expect(primary.requests.length, 1);
      expect(fallback.requests.length, 1);
      // The body survives the retry.
      expect(fallback.bodies.single, '{"email":"a@b.c"}');
    });

    test('treats a ClientException that wraps a connection error the same',
        () async {
      final primary = _FakeClient(
        (_) => throw http.ClientException('HandshakeException: Connection reset by peer'),
      );
      final fallback = _FakeClient((_) async => _ok('x'));
      final response = await make(primary, fallback).get(url);
      expect(response.body, 'x');
    });

    test('prefers the fallback after it worked, until the time is up', () async {
      var now = DateTime(2026, 11, 18, 12);
      final primary = _FakeClient((_) => throw const SocketException('reset'));
      final fallback = _FakeClient((_) async => _ok('x'));
      final client = make(primary, fallback, now: () => now);
      await client.get(url);
      expect(primary.requests.length, 1);
      await client.get(url); // goes straight to the fallback
      expect(primary.requests.length, 1);
      expect(fallback.requests.length, 2);
      now = now.add(const Duration(minutes: 11));
      await client.get(url); // back to the normal route first
      expect(primary.requests.length, 2);
    });

    test('does not retry real server answers, even errors', () async {
      final primary = _FakeClient((_) async => _ok('nope', 500));
      final fallback = _FakeClient((_) async => _ok('x'));
      final response = await make(primary, fallback).get(url);
      expect(response.statusCode, 500);
      expect(fallback.requests, isEmpty);
    });

    test('does not hide non-connection errors', () async {
      final primary = _FakeClient((_) => throw const FormatException('bug'));
      final fallback = _FakeClient((_) async => _ok('x'));
      expect(make(primary, fallback).get(url), throwsA(isA<FormatException>()));
      expect(fallback.requests, isEmpty);
    });

    test('reports the normal route\'s error when both routes fail', () async {
      final primary = _FakeClient((_) => throw const HandshakeException('first'));
      final fallback = _FakeClient((_) => throw const SocketException('second'));
      expect(make(primary, fallback).get(url), throwsA(isA<HandshakeException>()));
    });

    test('leaves other hosts and plain http alone', () async {
      final primary = _FakeClient((_) => throw const SocketException('down'));
      final fallback = _FakeClient((_) async => _ok('x'));
      final client = make(primary, fallback);
      await expectLater(
        client.get(Uri.parse('https://other.example.com/')),
        throwsA(isA<SocketException>()),
      );
      await expectLater(
        client.get(Uri.parse('http://$_host/')),
        throwsA(isA<SocketException>()),
      );
      expect(fallback.requests, isEmpty);
    });
  });

  group('DohTunnel', () {
    late DohTunnel tunnel;
    late int port;
    late ServerSocket upstream;
    final received = <String>[];

    setUp(() async {
      received.clear();
      // A stand-in for the real server: echoes whatever it gets, upper-cased.
      upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((socket) {
        socket.listen((data) {
          received.add(utf8.decode(data));
          socket.add(utf8.encode(utf8.decode(data).toUpperCase()));
        });
      });
      tunnel = DohTunnel(
        resolver: DohResolver(
          fetch: (_) async => _answer([
            {'type': 1, 'data': '104.18.38.10', 'TTL': 60},
          ]),
        ),
        allowedHosts: {_host},
        connector: (address, p) async {
          expect(address.address, '104.18.38.10');
          expect(p, 443);
          return Socket.connect(InternetAddress.loopbackIPv4, upstream.port);
        },
      );
      port = await tunnel.start();
    });

    tearDown(() async {
      await tunnel.close();
      await upstream.close();
    });

    Future<String> ask(String firstLine, {String? thenSend}) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final out = StringBuffer();
      final done = Completer<void>();
      socket.listen(
        (d) => out.write(utf8.decode(d)),
        onDone: done.complete,
        onError: (_) => done.complete(),
      );
      socket.write('$firstLine\r\nHost: x\r\n\r\n');
      if (thenSend != null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        socket.write(thenSend);
      }
      await Future.any([done.future, Future<void>.delayed(const Duration(seconds: 1))]);
      await socket.close();
      return out.toString();
    }

    test('tunnels an allowed host and passes bytes both ways', () async {
      final reply = await ask('CONNECT $_host:443 HTTP/1.1', thenSend: 'hello');
      expect(reply, startsWith('HTTP/1.1 200'));
      expect(reply, endsWith('HELLO'));
      expect(received, ['hello']);
    });

    test('refuses hosts, ports and methods it should not serve', () async {
      expect(await ask('CONNECT evil.example.com:443 HTTP/1.1'), startsWith('HTTP/1.1 403'));
      expect(await ask('CONNECT $_host:8080 HTTP/1.1'), startsWith('HTTP/1.1 403'));
      expect(await ask('GET / HTTP/1.1'), startsWith('HTTP/1.1 403'));
      expect(received, isEmpty);
    });
  });
}
