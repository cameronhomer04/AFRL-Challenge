/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           dashboard_screen.dart
Author:         Cameron Homer
Date:           10/05/2026
Description:    Handles the display of the application
*/

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/alert_data.dart';
import '../services/rest_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Stuff for controllers (RESTful Service and interactable box)
  String _hostIp = "10.0.2.2";
  String _port = "5000";
  late TextEditingController _ipController;
  late TextEditingController _portController;
  List<AlertData> _alerts = [
    AlertData(
      status: "SCANNING",
      centerFreq: 0.0,
      modulationType: "NONE",
      sdrNode: 0,
    ),
  ];
  Timer? _pollingTimer;
  final RestAlertService _alertService = RestAlertService();

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: _hostIp);
    _portController = TextEditingController(text: _port);
    startPolling();
  }

  void startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: 300), 
      (timer) async {
        final tempAlerts = await _alertService.getAlerts(_hostIp, _port);
        if (mounted && tempAlerts.isNotEmpty && !listEquals(_alerts, tempAlerts)){
          setState(() {_alerts = tempAlerts;});
        }
      }
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Worth noting that this will be 1 in the no alerts case b/c their will be a "SCANNING" Alert
    // I think it will be useful for if we want implementation for if multiple alerts are found (Thinking of make multiple blocks of the data?)
    //final int numAlerts = _alerts.length;
    final bool isAlertActive = _alerts[0].alertStatus;
    final double centerFrequency = _alerts[0].centerFreq; // Placeholder for actual center frequency logic
    final String modType = _alerts[0].modulationType; // Placeholder for actual modulation type logic
    final int sdrNode = _alerts[0].sdrNode; // Placeholder for actual SDR node logic

    // Determine the units of the center frequency based on its value
    String frequencyUnits = centerFrequency >= 1e9 ? "GHz" : "MHz";
    String formattedFrequency = frequencyUnits == "GHz"
        ? (centerFrequency / 1e9).toStringAsFixed(2)
        : (centerFrequency / 1e6).toStringAsFixed(2);

    // Build the dashboard UI
    return Scaffold(
      appBar: AppBar(
        title: const Text("Homebase Alerts"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: LayoutBuilder(
        builder: (context, constaints) {
          return SingleChildScrollView (
            child : ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constaints.maxHeight,
              ),
              child: IntrinsicHeight(
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
                      
                      // Only display metric data if in alert mode, otherwise hide these displays
                      if (isAlertActive) ...[
                        Row(
                          children: [
                            // Display the center frequency of the alert
                            Expanded(
                              child: _buildInfoBox(
                                "Center Frequency",
                                "$formattedFrequency $frequencyUnits",
                                Icons.radar,
                                const Color(0xFF1E1E1E),
                                Colors.white60,
                                Colors.greenAccent
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Display the modulation type of the alert
                            Expanded(
                              child: _buildInfoBox(
                                "Modulation Type",
                                modType,
                                Icons.graphic_eq,
                                const Color(0xFF1E1E1E),
                                Colors.white60,
                                Colors.greenAccent
                              ),
                            ),
                          ],
                        ),
                        // Add some spacing between the rows of boxes
                        const SizedBox(height: 24),

                        Row(
                          children: [
                            // Display the SDR Node that alerted
                            Expanded(
                              child: _buildInfoBox(
                                "SDR Node",
                                "$sdrNode",
                                Icons.router,
                                const Color(0xFF1E1E1E),
                                Colors.white60,
                                Colors.greenAccent
                              ),
                            ),
                          ]
                        ),
                      ],  // End of the conditional display of metric data boxes
                      const SizedBox(height: 24),
                      // Add IP Configuration box at bottom of dashboard
                      const Spacer(),
                      _buildConfigBox(
                        title: "Host IP Address",
                        activeValue: _hostIp,
                        controller: _ipController,
                        onSave: (newValue) {
                          setState(() => _hostIp = newValue);
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildConfigBox(
                        title: "Port",
                        activeValue: _port,
                        controller: _portController,
                        onSave: (newValue) {
                          setState(() => _port = newValue);
                        },
                      ),
                      const SizedBox(height: 24) // Add some spacing at the bottom
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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

  // Helper function to build data boxes for the dashboard
  Widget _buildInfoBox(String label, String value, IconData icon, Color boxColor, Color textColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      // Build a box with a border radius and a background color that can be customized
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(12.0),
      ),
      // Place an icon and text inside the box that can be customized
      child: Column(
        children: [
          // Icon in the box
          Icon(
            icon, 
            color: iconColor, 
            size: 28
          ),
          const SizedBox(height: 12),
          // Text for label
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // Text for value
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

/*
  // Helper function to build IP configuration box for the dashboard
  Widget _buildIPConfigBox() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Host IP Configuration",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Active: $_hostIp",
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController, 
                  decoration: InputDecoration(
                    hintText: "Enter Host IP Address",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              // Button to commit the typed value into state
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hostIp = _ipController.text.trim();
                  });
                  // Unfocus keyboard
                  FocusScope.of(context).unfocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortConfigBox() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Port Configuration",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Active: $_port",
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController, 
                  decoration: InputDecoration(
                    hintText: "Enter Port",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              // Button to commit the typed value into state
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _port = _portController.text.trim();
                  });
                  // Unfocus keyboard
                  FocusScope.of(context).unfocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
*/


  // New Interactable Generic Config Box (kept only method for git purposes since I think both ways work, I just KNOW that the old way does work)
  Widget _buildConfigBox({required String title, required String activeValue, required TextEditingController controller, required ValueChanged<String> onSave,}) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$title Configuration",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Active: $activeValue",
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller, 
                  decoration: InputDecoration(
                    hintText: "Enter $title",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              // Button to commit the typed value into state
              ElevatedButton(
                onPressed: () {
                  onSave(controller.text.trim());
                  // Unfocus keyboard
                  FocusScope.of(context).unfocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}