/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           foreground_task_handler.dart
Author:         Cameron Homer
Date:           10/30/2026
Description:    Setup the foreground task handler
*/

import 'dart:developer' as dev;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_data.dart';
import 'tcp_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AlertSystemTaskHandler());
}

class AlertSystemTaskHandler extends TaskHandler {
  TcpAlertService? _tcpService;
  NotificationService? _notificationService;
  StreamSubscription<List<AlertData>>? _alertSub;
  
  String _currentIp = '';
  String _currentPort = '';
  bool _isConnecting = false;

  String? _lastReceivedJSON;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _notificationService = NotificationService();
    await _notificationService?.init();
    await _connectSocketFromPrefs();
  }

  @override
  void onReceiveData(Object data) {
    dev.log('==== TASK HANDLER RECEIVED COMMAND: $data ====');
    if (data == 'RESET') {
      _tcpService?.sendResetCommand();
    } else if (data == 'GET_LAST_JSON') {
      if (_lastReceivedJSON != null) {
        dev.log('==== RETURNING CACHED ALERTS TO REOPENED UI ====');
        FlutterForegroundTask.sendDataToMain(_lastReceivedJSON!);
      }
    } else if (data is String) {
      try {
          final decoded = jsonDecode(data);
          if (decoded is Map && decoded['command'] == 'RECONNECT') {
            _connectSocketFromPrefs(
              forceReconnect: true,
              overrideIp: decoded['ip']?.toString(),
              overridePort: decoded['port']?.toString(),
            );
          }
        } catch (_) {
          // Fallback if plain 'RECONNECT' string is ever sent
          if (data == 'RECONNECT') {
            _connectSocketFromPrefs(forceReconnect: true);
          }
        }
    }
  }

  Future<void> _connectSocketFromPrefs({bool forceReconnect = false, String? overrideIp, String? overridePort}) async {
    if (_isConnecting) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final String hostIp = overrideIp ?? prefs.getString('server_ip') ?? '10.0.2.2';
      final String port = overridePort ?? prefs.getString('server_port') ?? '5000';

      // If already connected to the target IP & Port, do not tear down the socket!
      if (!forceReconnect && _tcpService != null && _currentIp == hostIp && _currentPort == port && _tcpService!.isConnected) {
        return;
      }

      _isConnecting = true;
      _currentIp = hostIp;
      _currentPort = port;

      await _alertSub?.cancel();
      await _tcpService?.dispose();

      _tcpService = TcpAlertService();

      _alertSub = _tcpService?.alertStream.listen((tempAlerts) {
        dev.log('==== Stream emitted ${tempAlerts.length} items ====');
        if (tempAlerts.isNotEmpty) {
          final rawJsonList = tempAlerts.map((a) => a.toJson()).toList();
          final String jsonString = jsonEncode(rawJsonList);
          dev.log('==== Sending data to main: $jsonString ====');
          _lastReceivedJSON = jsonString;
          // Send encoded JSON payload to UI
          FlutterForegroundTask.sendDataToMain(jsonString);

          final bool currentlyActive = tempAlerts.any((a) => a.alertStatus);

          if (currentlyActive) {
            dev.log("==== ALERTS DETECTED: ${tempAlerts.where((a) => a.alertStatus).length} ACTIVE THREAT(S) ====");
            final uniqueId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            _notificationService?.showAlertNotification(
              id: uniqueId,
              title: "DRONE THREAT DETECTED",
              body: "${tempAlerts.where((a) => a.alertStatus).length} active threat(s) detected across SDR nodes",
            );
          } else {
            FlutterForegroundTask.updateService(
              notificationTitle: 'System Operational',
              notificationText: 'Monitoring server ($hostIp:$port) for alerts',
            );
          }
        }
      });

      FlutterForegroundTask.updateService(
        notificationTitle: 'AFRL Alert System',
        notificationText: 'Connecting to server ($hostIp:$port)...',
      );

      await _tcpService?.connect(_currentIp, _currentPort);
    } catch (e, stack) {
      dev.log("==== ERROR CONNECTING TO TCP SOCKET: $e ====");
      dev.log(stack.toString());
    } finally {
      _isConnecting = false;
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Only attempt reconnect if the socket is actually disconnected!
    if (_tcpService == null || !_tcpService!.isConnected) {
      await _connectSocketFromPrefs();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _alertSub?.cancel();
    await _tcpService?.dispose();
    _tcpService = null;
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}