// Live latency to a server, shown under its name. Android can't do raw ICMP
// without root, so we measure the TCP-connect RTT to the node's Reality port
// (same network round-trip a ping would report). Colour-coded:
//   < 100 ms  green   ·   100–300 ms  yellow   ·   ≥ 300 ms  red.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';

/// TCP-connect ping. Returns round-trip ms, or null on failure/timeout.
Future<int?> tcpPing(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final sw = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    socket?.destroy();
  }
}

class PingLabel extends StatefulWidget {
  const PingLabel({super.key, required this.host, required this.port});
  final String? host;
  final int port;

  @override
  State<PingLabel> createState() => _PingLabelState();
}

class _PingLabelState extends State<PingLabel> {
  int? _ms;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final host = widget.host;
    if (host == null || host.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    final ms = await tcpPing(host, widget.port);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = ms == null;
      _ms = ms;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Cosmic.muted),
          ),
          SizedBox(width: 6),
          Text('пинг…', style: TextStyle(color: Cosmic.muted, fontSize: 12)),
        ],
      );
    }
    if (_failed || _ms == null) {
      return const Text('недоступен', style: TextStyle(color: Cosmic.muted, fontSize: 12));
    }
    final ms = _ms!;
    final color = ms < 100
        ? const Color(0xFF2FE6A7) // green
        : ms < 300
            ? const Color(0xFFFFC857) // yellow
            : Cosmic.error; // red
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$ms мс', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
