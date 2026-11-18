import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// Some networks answer DNS lookups for our Supabase project with the wrong
// address. The app then reaches a server that isn't Supabase and fails with a
// handshake or connection-reset error. This file makes the app recover on its
// own: if the normal connection fails, it asks an encrypted DNS service
// (DNS-over-HTTPS) for the real address and connects there instead.
//
// The certificate is still checked against the real host name, so a wrong or
// fake server is still rejected. No address is hardcoded: it is looked up
// each time. The only things sent to the DNS services are host names.

/// Looks up IPv4 addresses with DNS-over-HTTPS. The DNS services are reached
/// by their fixed public addresses, so no ordinary DNS lookup is needed.
class DohResolver {
  DohResolver({
    List<Uri>? endpoints,
    @visibleForTesting this.fetch,
    this.timeout = const Duration(seconds: 4),
    DateTime Function()? now,
  }) : endpoints = endpoints ?? defaultEndpoints,
       _now = now ?? DateTime.now;

  /// Cloudflare first, then Google.
  static final List<Uri> defaultEndpoints = [
    Uri.parse('https://1.1.1.1/dns-query'),
    Uri.parse('https://8.8.8.8/resolve'),
  ];

  final List<Uri> endpoints;
  final Duration timeout;
  /// Replaces the real network call (for tests).
  final Future<String> Function(Uri url)? fetch;
  final DateTime Function() _now;
  final Map<String, (List<InternetAddress>, DateTime)> _cache = {};

  /// The addresses for [host]. Answers are cached for their time-to-live,
  /// kept between 30 seconds and 5 minutes. Throws a [SocketException] if no
  /// DNS service gives a usable answer.
  Future<List<InternetAddress>> resolve(String host) async {
    final key = host.toLowerCase();
    final cached = _cache[key];
    if (cached != null && _now().isBefore(cached.$2)) return cached.$1;

    for (final endpoint in endpoints) {
      try {
        final url = endpoint.replace(
          queryParameters: {'name': key, 'type': 'A'},
        );
        final body = await (fetch ?? _defaultFetch)(url).timeout(timeout);
        final answer = parseAnswer(body);
        if (answer.$1.isNotEmpty) {
          final ttl = answer.$2.clamp(30, 300);
          _cache[key] = (answer.$1, _now().add(Duration(seconds: ttl)));
          return answer.$1;
        }
      } catch (_) {
        // Try the next DNS service.
      }
    }
    throw SocketException('DNS-over-HTTPS lookup failed for $host');
  }

  /// Reads the addresses and the smallest time-to-live (seconds) out of a
  /// DNS-over-HTTPS JSON answer. Only usable IPv4 addresses are kept.
  @visibleForTesting
  static (List<InternetAddress>, int) parseAnswer(String body) {
    final json = jsonDecode(body);
    final answers = json is Map ? json['Answer'] : null;
    final addresses = <InternetAddress>[];
    var ttl = 300;
    if (answers is List) {
      for (final entry in answers) {
        if (entry is! Map || entry['type'] != 1) continue;
        final address = InternetAddress.tryParse('${entry['data']}');
        if (address == null ||
            address.type != InternetAddressType.IPv4 ||
            address.isLoopback ||
            address.address == '0.0.0.0') {
          continue;
        }
        addresses.add(address);
        final entryTtl = entry['TTL'];
        if (entryTtl is int && entryTtl < ttl) ttl = entryTtl;
      }
    }
    return (addresses, ttl);
  }

  Future<String> _defaultFetch(Uri url) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url);
      request.headers.set('accept', 'application/dns-json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('DNS-over-HTTPS returned ${response.statusCode}');
      }
      return await utf8.decodeStream(response);
    } finally {
      client.close(force: true);
    }
  }
}

/// A small tunnel that listens only on this device (127.0.0.1). A client that
/// uses it as its proxy asks for `CONNECT host:443`; the tunnel looks the host
/// up with [resolver], connects to the real address and passes the bytes both
/// ways. The TLS handshake stays between the client and the real server, so
/// the tunnel never sees the data and the certificate is still checked.
///
/// It only tunnels to [allowedHosts] on port 443, so it can't be used as an
/// open proxy by anything else on the device.
class DohTunnel {
  DohTunnel({
    required this.resolver,
    required Set<String> allowedHosts,
    this.connectTimeout = const Duration(seconds: 6),
    @visibleForTesting this.connector,
  }) : allowedHosts = {for (final host in allowedHosts) host.toLowerCase()};

  final DohResolver resolver;
  final Set<String> allowedHosts;
  final Duration connectTimeout;

  /// Replaces the real connection (for tests).
  final Future<Socket> Function(InternetAddress address, int port)? connector;
  ServerSocket? _server;

  /// Starts listening and returns the local port. Safe to call twice.
  Future<int> start() async {
    final existing = _server;
    if (existing != null) return existing.port;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close();
  }

  void _handle(Socket client) {
    final head = BytesBuilder();
    Socket? upstream;
    var opening = false;
    late final StreamSubscription<Uint8List> subscription;

    void reject(String status) {
      client.write('HTTP/1.1 $status\r\nConnection: close\r\n\r\n');
      client.close();
    }

    subscription = client.listen(
      (data) {
        final open = upstream;
        if (open != null) {
          open.add(data);
          return;
        }
        if (opening) return;
        head.add(data);
        final bytes = head.toBytes();
        final end = _headerEnd(bytes);
        if (end < 0) {
          if (bytes.length > 8192) reject('431 Request Header Fields Too Large');
          return;
        }
        opening = true;
        subscription.pause();
        _open(String.fromCharCodes(bytes, 0, end)).then((socket) {
          upstream = socket;
          client.write('HTTP/1.1 200 Connection established\r\n\r\n');
          final leftover = end + 4 < bytes.length
              ? bytes.sublist(end + 4)
              : Uint8List(0);
          if (leftover.isNotEmpty) socket.add(leftover);
          socket.listen(
            client.add,
            onDone: () => client.close(),
            onError: (_) => client.destroy(),
            cancelOnError: true,
          );
          subscription.resume();
        }, onError: (Object error) {
          reject(error is _Refused ? '403 Forbidden' : '502 Bad Gateway');
        });
      },
      onDone: () => upstream?.close(),
      onError: (_) => upstream?.destroy(),
      cancelOnError: true,
    );
  }

  /// Checks the CONNECT line and connects to the first address that answers.
  Future<Socket> _open(String head) async {
    final line = head.split('\r\n').first.split(' ');
    if (line.length < 2 || line[0].toUpperCase() != 'CONNECT') {
      throw const _Refused();
    }
    final target = line[1];
    final colon = target.lastIndexOf(':');
    if (colon <= 0) throw const _Refused();
    final host = target.substring(0, colon).toLowerCase();
    final port = int.tryParse(target.substring(colon + 1));
    if (port == null || port != 443 || !allowedHosts.contains(host)) {
      throw const _Refused();
    }

    Object? lastError;
    for (final address in await resolver.resolve(host)) {
      try {
        final connect = connector;
        return connect != null
            ? await connect(address, port)
            : await Socket.connect(address, port, timeout: connectTimeout);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const SocketException('No address to connect to');
  }

  static int _headerEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}

class _Refused implements Exception {
  const _Refused();
}

/// An HTTP client that connects normally, and if that fails because the
/// network can't reach the server (wrong DNS answer, handshake error,
/// connection reset), retries through [DohTunnel]. Once the retry works it
/// tries that route first for [preferFallbackFor], so later calls are quick.
///
/// Only requests to [hosts] over HTTPS get the retry; everything else goes
/// straight through. Responses with an error status (400, 500...) are real
/// answers from the server and are never retried.
class DohFallbackClient extends http.BaseClient {
  DohFallbackClient({
    required Set<String> hosts,
    DohResolver? resolver,
    this.preferFallbackFor = const Duration(minutes: 10),
    @visibleForTesting http.Client? primary,
    @visibleForTesting http.Client? fallback,
    @visibleForTesting DateTime Function()? now,
  }) : _hosts = {for (final host in hosts) host.toLowerCase()},
       _primary =
           primary ?? IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 15)),
       _injectedFallback = fallback,
       _now = now ?? DateTime.now,
       _tunnel = fallback == null
           ? DohTunnel(resolver: resolver ?? DohResolver(), allowedHosts: hosts)
           : null;

  final Set<String> _hosts;
  final Duration preferFallbackFor;
  final http.Client _primary;
  final http.Client? _injectedFallback;
  final DohTunnel? _tunnel;
  final DateTime Function() _now;
  Future<http.Client>? _fallbackFuture;
  DateTime? _preferFallbackUntil;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final eligible =
        request.url.scheme == 'https' &&
        _hosts.contains(request.url.host.toLowerCase());
    if (!eligible) return _primary.send(request);

    // A request body can only be read once, so keep it for a possible retry.
    final body = await request.finalize().toBytes();
    http.Request copy() => http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = body;

    Future<http.StreamedResponse> viaPrimary() => _primary.send(copy());
    Future<http.StreamedResponse> viaFallback() async {
      final client = await _fallbackClient();
      final response = await client.send(copy());
      _preferFallbackUntil = _now().add(preferFallbackFor);
      return response;
    }

    final until = _preferFallbackUntil;
    final fallbackFirst = until != null && _now().isBefore(until);
    final first = fallbackFirst ? viaFallback : viaPrimary;
    final second = fallbackFirst ? viaPrimary : viaFallback;

    Object? primaryError;
    try {
      return await first();
    } catch (error) {
      if (!isConnectionProblem(error)) rethrow;
      if (!fallbackFirst) primaryError = error;
    }
    try {
      return await second();
    } catch (error) {
      if (!isConnectionProblem(error)) rethrow;
      if (fallbackFirst) primaryError = error;
      // Report the normal route's error: it is the one users would expect.
      // ignore: only_throw_errors
      throw primaryError ?? error;
    }
  }

  /// True for errors that mean "couldn't reach the server", not for answers
  /// the server actually gave.
  @visibleForTesting
  static bool isConnectionProblem(Object error) {
    if (error is SocketException ||
        error is HandshakeException ||
        error is TlsException ||
        error is TimeoutException) {
      return true;
    }
    // The http package wraps these inside a ClientException.
    if (error is http.ClientException) {
      final text = error.toString();
      return text.contains('SocketException') ||
          text.contains('HandshakeException') ||
          text.contains('TlsException') ||
          text.contains('Connection reset') ||
          text.contains('Connection refused') ||
          text.contains('Connection terminated');
    }
    return false;
  }

  Future<http.Client> _fallbackClient() {
    final injected = _injectedFallback;
    if (injected != null) return Future.value(injected);
    return _fallbackFuture ??= () async {
      final port = await _tunnel!.start();
      return IOClient(
        HttpClient()
          ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
          ..connectionTimeout = const Duration(seconds: 20),
      );
    }();
  }

  @override
  void close() {
    _primary.close();
    _injectedFallback?.close();
    _fallbackFuture?.then((client) => client.close());
    _tunnel?.close();
  }
}
