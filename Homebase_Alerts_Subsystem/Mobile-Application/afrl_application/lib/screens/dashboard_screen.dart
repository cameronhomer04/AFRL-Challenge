/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           dashboard_screen.dart
Author:         Cameron Homer
Date:           10/26/2026
Description:    Handles the display of the application with tcp service
*/

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'configuration_screen.dart';
import 'reset_screen.dart';
import '../models/alert_data.dart';
import '../models/box_data.dart';
import '../services/tcp_service.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Stuff for controllers (RESTful Service and interactable box)
  String _hostIp = "10.0.2.2";
  String _port = "5000";
  List<AlertData> _alerts = [
    AlertData(
      status: "SCANNING",
      centerFreq: 0.0,
      modulationType: "NONE",
      sdrNode: 0,
    ),
  ];
  final TcpAlertService _tcpService = TcpAlertService();
  StreamSubscription<List<AlertData>>? _alertSubscription;
  bool _wasAlertActive = false;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _notificationService.init();
    _setupTcpListener();
    _tcpService.connect(_hostIp, _port);
  }

  void _setupTcpListener() {
    _alertSubscription = _tcpService.alertStream.listen((tempAlerts) {
      if (mounted && tempAlerts.isNotEmpty && !listEquals(_alerts, tempAlerts)) {
        final bool currentlyActive = tempAlerts.any((a) => a.alertStatus);
        
        // Trigger notification when transitioning into an alert state
        if (currentlyActive && !_wasAlertActive) {
          final uniqueId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          _notificationService.showAlertNotification(
            id: uniqueId,
            title: "DRONE THREAT DETECTED",
            body: "${tempAlerts.where((a) => a.alertStatus).length} active threat(s) detected across SDR nodes",
          );
        }

        setState(() {
          _alerts = tempAlerts;
          _wasAlertActive = currentlyActive;
        });
      }
    });
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _tcpService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isAlertActive = _alerts.any((alert) => alert.alertStatus);

    // Build the dashboard UI
    return Scaffold(
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
                builder: (context) => ResetScreen(
                  tcpService: _tcpService,
                ),
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
                    onSave: (newIp, newPort) {
                      setState(() {
                        _hostIp = newIp;
                        _port = newPort;
                      });
                      // Re-trigger polling loop with new IP/Port
                      _tcpService.connect(_hostIp, _port);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView (
        // This prevents the user's over scrolling to stretch the dashboard. Instead it just sort of scrolls further into nothing. May perfer the stretch idk
        physics: const BouncingScrollPhysics(),
        child: Padding (
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Display the current alert status
              Row(
                children: [
                  Expanded(
                    child: _buildAlertBox(
                      isAlertActive ? "ALERT ACTIVE" : "SCANNING ACTIVE",
                      isAlertActive ? Icons.warning_amber_rounded : Icons.task_alt_rounded,
                      isAlertActive ? Colors.redAccent : Colors.greenAccent,
                      isAlertActive ? Colors.red : Colors.green,
                      Colors.black,
                      isAlertActive ? Colors.red : Colors.green
                    ),
                  ),
                ],
              ),
              // Add some spacing between the rows of boxes
              const SizedBox(height: 24),
              // Display all alerts
              for (final alert in _alerts.where((alert) => alert.alertStatus)) ...[
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
                ), // _buildDataBox
                const SizedBox(height: 24),
              ],
            ],
          ),
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