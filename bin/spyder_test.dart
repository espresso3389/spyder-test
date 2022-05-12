import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:synchronized/extension.dart';
import 'package:udp/udp.dart';

class Spyder {
  final Endpoint destination;
  UDP? _udp;
  StreamSubscription<Datagram?>? _sub;

  Spyder({required this.destination});
  Spyder.fromAddress(InternetAddress address, {Port port = _spyderPort})
      : destination = Endpoint.unicast(address, port: port);
  factory Spyder.fromAddressString(String address, {Port port = _spyderPort}) =>
      Spyder.fromAddress(InternetAddress.tryParse(address)!, port: port);

  Future<void> _ensureInit() => synchronized(
        () async {
          if (_udp != null) return;
          _udp = await UDP.bind(Endpoint.any(port: _spyderPort));
          _sub = _udp!.asStream().listen((datagram) {
            if (datagram != null) {
              _handleResponse(ascii.decode(datagram.data, allowInvalid: true));
            }
          });
        },
      );

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _udp?.close();
    _udp = null;
  }

  Future<void> send(String command) async {
    await _ensureInit();
    final data = [
      0x73,
      0x70,
      0x79,
      0x64,
      0x65,
      0x72,
      0,
      0,
      0,
      0,
      ...ascii.encode(command)
    ];
    await _udp!.send(data, destination);
  }

  void _handleResponse(String response) {
    final res = SpyderResponse.fromResponse(response);
    print('S: $res');
  }

  static const _spyderPort = Port(11116);
}

class SpyderResponse {
  final SpyderResponseCode code;
  final List<String> args;
  const SpyderResponse.fromCodeAndArgs(
      {required this.code, required this.args});

  factory SpyderResponse.fromResponse(String response) {
    final args = response.split(' ');
    return SpyderResponse.fromCodeAndArgs(
      code: SpyderResponseCode.values[int.parse(args[0])],
      args: args.skip(1).map((s) => s.replaceAll('%20', ' ')).toList(),
    );
  }

  @override
  String toString() {
    return args.isEmpty ? '$code' : '$code: [${args.join(',')}]';
  }
}

/// Command processor responses
enum SpyderResponseCode {
  /// The command was successfully processed.
  success,

  /// The data requested is not available.
  empty,

  /// An invalid command was specified.
  header,

  /// The command is missing the required minimum number of
  argumentCount,

  /// One or more arguments of the command were invalid.
  argumentValue,

  /// An error occurred while processing the command. For details, check the Alert Viewer in Spyder Studio.
  execution,

  /// Reserved.
  checksum,
}

void main(List<String> arguments) async {
  final s = Spyder.fromAddressString(arguments[0]);

  await s.send("RLN");

  // //await s.send("LAP 1 0 2 3 4");
  // await s.send("TRN 0 60 2 3 4");
  // await Future.delayed(Duration(seconds: 1));

  // for (int i = 0; i < 2; i++) {
  //   await s.send("LSP 0 ${i * 3840} 0 3840 ${i + 2}");
  // }
  // await s.send("LSP 0 0 0 100 4");

  // await s.send("TRN 1 60 2 3 4");
  // await Future.delayed(Duration(seconds: 1));

  // for (int i = 0; i < 3840; i += 5) {
  //   await Future.delayed(Duration(milliseconds: 2));

  //   await s.send("LSP 0 $i 0 ${i + 100} 4");
  // }

  // for (int i = 0; i < 3840; i += 5) {
  //   await Future.delayed(Duration(milliseconds: 5));

  //   await s.send("LSP 0 $i 0 ${i + 100} 4");
  // }

  // for (int i = 0; i < 3840; i += 5) {
  //   await Future.delayed(Duration(milliseconds: 10));

  //   await s.send("LSP 0 $i 0 ${i + 100} 4");
  // }

  final finish = Completer<int>();
  final sub = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) async {
    if (line.isEmpty) {
      finish.complete(1);
      print('Quit');
      return;
    }
    print('C: $line');
    await s.send(line);
  });
  await finish.future;
  sub.cancel();
  s.dispose();
}
