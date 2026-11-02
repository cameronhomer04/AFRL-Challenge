/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           main.dart
Author:         Cameron Homer
Date:           10/05/2026
Description:    Basic setup for mobile application
*/

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/dashboard_screen.dart';
import 'services/controller_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  ForegroundTaskController.initService();
  runApp(const AFRLAlertApp());
}

class AFRLAlertApp extends StatelessWidget {
  const AFRLAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AFRL Tactical Alert System',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
