/// Discovery over UDP for Android, Windows, iOS, macOS and Linux.
///
/// One probe goes to each place the laptop might hear it, and every verified
/// announce that comes back before the timeout is kept:
///
///   * 255.255.255.255 - the limited broadcast. Windows only sends it out of
///     one adapter, so on its own it can miss the right network;
///   * the /24 directed broadcast (a.b.c.255) of each of this device's own
///     IPv4 addresses, which does go out of the matching adapter. /24 is an
///     assumption - dart:io does not report prefix lengths - but it is what
///     home, office and hotspot networks use, and a wider network still
///     receives the limited broadcast;
///   * 127.0.0.1, for the app running on the laptop itself.
///
/// The probe is sent twice, a third of the way apart, because a Wi-Fi
/// broadcast is sent once, unacknowledged, at the lowest data rate, and a
/// single lost datagram should not mean "no server". The server allows 30
/// probes a minute per address, far more than a search sends.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_ai_discovery.dart';

const bool discoverySupported = true;

Future<List<LocalAiDiscoveredServer>> discover({
  required String apiKey,
  required String keyId,
  required int port,
  required Duration timeout,
}) async {
  final nonce = LocalAiDiscoveryProtocol.newNonce();
  final probe = LocalAiDiscoveryProtocol.encodeProbe(
    apiKey: apiKey,
    keyId: keyId,
    nonce: nonce,
  );

  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } on SocketException catch (error) {
    // No IPv4 networking at all (flight mode): there is nobody to ask.
    debugPrint('Local AI discovery: could not open a UDP socket (${error.message})');
    return const [];
  }
  socket.broadcastEnabled = true;

  final found = <String, LocalAiDiscoveredServer>{};

  // Probes waiting to go out. send() returns 0 - and drops the datagram -
  // when the socket cannot take another one yet, which on Windows happens
  // after only two back-to-back broadcasts. So the rest wait for the socket
  // to say it is writable again rather than being lost silently.
  final pending = <InternetAddress>[];

  void flush() {
    while (pending.isNotEmpty) {
      final target = pending.first;
      final int sent;
      try {
        sent = socket.send(probe, target, port);
      } on SocketException {
        // e.g. no route for a broadcast on this adapter. Best effort: the
        // other targets may still reach the laptop.
        pending.removeAt(0);
        continue;
      }
      if (sent == 0) {
        socket.writeEventsEnabled = true;
        return;
      }
      pending.removeAt(0);
    }
  }

  final subscription = socket.listen(
    (event) {
      if (event == RawSocketEvent.write) {
        flush();
        return;
      }
      if (event != RawSocketEvent.read) return;
      for (var datagram = socket.receive();
          datagram != null;
          datagram = socket.receive()) {
        final server = LocalAiDiscoveryProtocol.parseAnnounce(
          datagram.data,
          apiKey: apiKey,
          keyId: keyId,
          nonce: nonce,
        );
        if (server != null) found.putIfAbsent(server.identity, () => server);
      }
    },
    // A late ICMP "port unreachable" can surface as a socket error on some
    // platforms. It says nothing about the servers that did answer.
    onError: (Object error) =>
        debugPrint('Local AI discovery: socket error ($error)'),
  );

  try {
    final targets = await _targets();

    void sendAll() {
      pending.addAll(targets.where((t) => !pending.contains(t)));
      flush();
    }

    sendAll();
    await Future<void>.delayed(timeout ~/ 3);
    sendAll();
    await Future<void>.delayed(timeout - timeout ~/ 3);
  } finally {
    await subscription.cancel();
    socket.close();
  }

  return List.unmodifiable(found.values);
}

/// Where to send the probe; see the library comment.
Future<List<InternetAddress>> _targets() async {
  final targets = <String>{'255.255.255.255'};

  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        // Self-assigned (169.254.x.x): no DHCP answered, so no laptop either.
        if (parts[0] == '169' && parts[1] == '254') continue;
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
  } catch (error) {
    // Some platforms restrict listing interfaces; the limited broadcast and
    // loopback still go out.
    debugPrint('Local AI discovery: could not list network interfaces ($error)');
  }

  targets.add('127.0.0.1');
  return [for (final t in targets) InternetAddress(t)];
}
