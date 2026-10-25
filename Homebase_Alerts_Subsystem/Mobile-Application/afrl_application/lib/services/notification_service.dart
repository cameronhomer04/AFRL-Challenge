/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           notification_service.dart
Author:         Cameron Homer
Date:           10/17/2026
Description:    Handles the push notification capabilities of the application
*/

import "package:flutter_local_notifications/flutter_local_notifications.dart";
//mport 'package:flutter/material.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings("@mipmap/ic_launcher");
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: androidSettings, 
      iOS: iosSettings,
    );
    await notificationsPlugin.initialize(initializationSettings);

    // This is needed for app to request permission to notify
    await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  }

  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          "drone_alert_channel",
          "UAV Alert Notification",
          channelDescription: "UAV Alert notification channel",
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}