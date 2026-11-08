/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           dashboard_screen.dart
Author:         Cameron Homer
Date:           10/26/2026
Description:    Handles the display of the application with tcp service
*/

import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:convert';

import 'configuration_screen.dart';
import 'reset_screen.dart';
import '../models/alert_data.dart';
import '../models/box_data.dart';
import '../services/controller_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _hostIp = "10.0.2.2";
  String _port = "5000";

  // 1. Define your own ValueNotifier to pass into ValueListenableBuilder
  final ValueNotifier<List<AlertData>> _alertsNotifier = ValueNotifier([
    AlertData(
      status: "SCANNING",
      centerFreq: 0.0,
      modulationType: "NONE",
      sdrNode: 0,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    // 2. Register the callback with flutter_foreground_task
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    _loadSavedConfigAndStart();
  }

  @override
  void dispose() {
    // Clean up both the callback and notifier when unmounting
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _alertsNotifier.dispose();
    super.dispose();
  }

  // 3. Update the ValueNotifier whenever new isolate data arrives
  void _onReceiveTaskData(Object data) {
    dev.log("==== ISOLATE DATA RECEIVED IN UI: $data ====");

    try {
      List<dynamic> parsedList = [];

      if (data is String) {
        parsedList = jsonDecode(data) as List<dynamic>;
      } else if (data is List) {
        parsedList = data;
      }

      final List<AlertData> newAlerts = parsedList.map((item) {
        final Map<String, dynamic> jsonMap = {};
        if (item is Map) {
          item.forEach((key, value) {
            jsonMap[key.toString()] = value;
          });
        }
        return AlertData.fromJson(jsonMap);
      }).toList();

      if (newAlerts.isNotEmpty) {
        // Assigning a new list triggers ValueListenableBuilder automatically!
        _alertsNotifier.value = newAlerts;
        dev.log("==== DASHBOARD NOTIFIER UPDATED WITH ${newAlerts.length} ALERTS ====");
      }
    } catch (e, stack) {
      dev.log("==== PARSING ERROR IN DASHBOARD: $e ====");
      dev.log(stack.toString());
    }
  }

  Future<void> _loadSavedConfigAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    if(mounted){
      setState(() {
        _hostIp = prefs.getString('server_ip') ?? "10.0.2.2";
        _port = prefs.getString('server_port') ?? "5000";
      });
    }

    if(!await FlutterForegroundTask.isRunningService){
      await ForegroundTaskController.startService(_hostIp, _port);
    } else {
      FlutterForegroundTask.sendDataToTask('GET_LAST_JSON');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Homebase Alerts"),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E1E1E),
          leading: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Reset System",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ResetScreen(),
                ),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: "Settings",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConfigurationScreen(
                      currentIp: _hostIp,
                      currentPort: _port,
                      onSave: (newIp, newPort) async {
                        setState(() {
                          _hostIp = newIp;
                          _port = newPort;
                        });
                        FlutterForegroundTask.sendDataToTask('RECONNECT');
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        // 4. ValueListenableBuilder listens directly to _alertsNotifier!
        body: ValueListenableBuilder<List<AlertData>>(
          valueListenable: _alertsNotifier,
          builder: (context, alerts, child) {
            final bool isAlertActive = alerts.any((alert) => alert.alertStatus);

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildAlertBox(
                            isAlertActive ? "ALERT ACTIVE" : "SCANNING ACTIVE",
                            isAlertActive ? Icons.warning_amber_rounded : Icons.task_alt_rounded,
                            isAlertActive ? Colors.redAccent : Colors.greenAccent,
                            isAlertActive ? Colors.red : Colors.green,
                            Colors.black,
                            isAlertActive ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    for (final alert in alerts.where((alert) => alert.alertStatus)) ...[
                      _buildDataBox(
                        BoxData(
                          label: "Center Frequency",
                          value: alert.centerFreq >= 1e3
                              ? "${(alert.centerFreq / 1e3).toStringAsFixed(2)} GHz"
                              : "${alert.centerFreq.toStringAsFixed(2)} MHz",
                          icon: Icons.radar,
                        ),
                        BoxData(
                          label: "Modulation Type",
                          value: alert.modulationType,
                          icon: Icons.graphic_eq,
                        ),
                        BoxData(
                          label: "SDR Node",
                          value: "${alert.sdrNode}",
                          icon: Icons.router,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Helper function to build alert box for the dashboard
  Widget _buildAlertBox(String label, IconData icon, Color boxColor, Color borderColor, Color textColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      // Build a box with a border radius and a background color that can be customized
      decoration: BoxDecoration(
        color: boxColor,
        border: Border.all(
                  color: borderColor,
                  width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      // Place an icon and text inside the box that can be customized
      child: Row(
        children: [
          // Icon in the box
          Icon(
            icon, 
            color: iconColor, 
            size: 36
          ),
          const SizedBox(width: 16),
          // Text for label
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      )
    );
  }

  // Helper function to build a singular alert data box
  Widget _buildDataBox(BoxData centerFreqBox, BoxData modTypeBox, BoxData sdrNodeBox){
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildInfoBox(sdrNodeBox)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildInfoBox(centerFreqBox)),
              const SizedBox(width: 12),
              Expanded(child: _buildInfoBox(modTypeBox)),
            ],
          ),
        ],
      ),
    );
  }

  // Helper function to build data boxes for the dashboard
  Widget _buildInfoBox(BoxData data) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      // Build a box with a border radius and a background color that can be customized
      decoration: BoxDecoration(
        color: data.boxColor,
        borderRadius: BorderRadius.circular(12.0),
      ),
      // Place an icon and text inside the box that can be customized
      child: Column(
        children: [
          // Icon in the box
          Icon(
            data.icon, 
            color: data.iconColor, 
            size: 28
          ),
          const SizedBox(height: 12),
          // Text for label
          Text(
            data.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: data.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // Text for value
          Text(
            data.value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: data.textColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}