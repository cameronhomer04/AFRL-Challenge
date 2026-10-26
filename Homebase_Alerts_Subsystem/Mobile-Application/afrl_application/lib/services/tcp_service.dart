/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           configuration_screen.dart
Author:         Cameron Homer
Date:           10/25/2026
Description:    Updated Raw TCPSocket server implementation for speed and battery improvement
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/alert_data.dart';

class TcpAlertService {
  Socket? _socket;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  final _alertController = StreamController<List<AlertData>>.broadcast();

  String _hostIp = "10.0.2.2";
  String _port = "5000";
  bool _shouldReconnect = true;
  bool _isConnected = false;

  /// Stream of live alert updates pushed from the server
  Stream<List<AlertData>> get alertStream => _alertController.stream;

  /// Connects to the raw TCP server and listens for line-delimited JSON
  Future<void> connect(String hostIp, String port) async {
    _hostIp = hostIp;
    _port = port;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    await _cleanupSocket();

    try {
      final int portNum = int.parse(_port);
      _socket = await Socket.connect(_hostIp, portNum, timeout: const Duration(seconds: 5));
      _isConnected = true;

      // We do this to make matlab recognize the tcp socket handshake
      _socket!.write('INIT\n');
      await _socket!.flush();

      _subscription = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
        if (line.trim().isNotEmpty) {
          try {
            var data = jsonDecode(line) as List<dynamic>;
            List<AlertData> dataList = data.map((d) => AlertData.fromJson(d)).toList();
            _alertController.add(dataList);
          } catch (err) {
            // Drop malformed frames silently
          }
        }
      }, onError: (err) {
        _handleDisconnect();
      }, onDone: () {
        _handleDisconnect();
      });
    } 
    catch (err) {
      _handleDisconnect();
    }
  }

  /// Sends the intentional RESET command string over the active TCP pipe
  Future<void> sendResetCommand() async {
    if (_socket != null && _isConnected) {
      try {
        _socket!.write('RESET\n');
        await _socket!.flush();
      } 
      catch (err) {
        // socket write error
      }
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _cleanupSocket();
    if(_shouldReconnect){
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        if(_shouldReconnect) {
          connect(_hostIp, _port);
        }
      });
    }
  }

  Future<void> _cleanupSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
  }

  Future<void> dispose() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    await _cleanupSocket();
  }
}