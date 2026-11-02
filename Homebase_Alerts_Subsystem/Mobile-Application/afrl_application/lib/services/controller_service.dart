/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           service_controller.dart
Author:         Cameron Homer
Date:           10/30/2026
Description:    Controls foreground service startup and persistent configuration storage
*/

import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'foreground_task_handler.dart';

class ForegroundTaskController {
  static void initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'drone_alert_channel',
        channelName: 'UAV Alert Monitoring',
        channelDescription: 'Maintains persistent TCP socket connection to MATLAB',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(), // Prevents repeat event interruptions
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> startService(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    await prefs.setString('server_port', port);

    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'AFRL Alert System',
        notificationText: 'Connecting to server',
        callback: startCallback,
      );
    }
  }

  static Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }
}