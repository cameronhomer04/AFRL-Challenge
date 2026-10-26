/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           configuration_screen.dart
Author:         Cameron Homer
Date:           10/17/2026
Description:    Handles the user configuration of IP Address and Port
*/

import 'package:flutter/material.dart';

class ConfigurationScreen extends StatefulWidget {
  final String currentIp;
  final String currentPort;
  final Function(String newIp, String newPort) onSave;

  const ConfigurationScreen({
    super.key,
    required this.currentIp,
    required this.currentPort,
    required this.onSave,
  });

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late String _activeIp;
  late String _activePort;

  @override
  void initState() {
    super.initState();
    _activeIp = widget.currentIp;
    _activePort = widget.currentPort;
    _ipController = TextEditingController(text: "");
    _portController = TextEditingController(text: "");
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _handleSaveIp(String newIp) {
    setState(() {
      _activeIp = newIp;
    });
    widget.onSave(_activeIp, _activePort);
    _showSuccessSnackBar("Host IP updated to $_activeIp");
  }

  void _handleSavePort(String newPort) {
    setState(() {
      _activePort = newPort;
    });
    widget.onSave(_activeIp, _activePort);
    _showSuccessSnackBar("Port updated to $_activePort");
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.greenAccent,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Server Settings"),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildConfigBox(
              title: "Host IP Address",
              activeValue: _activeIp,
              controller: _ipController,
              onSave: _handleSaveIp,
            ),
            const SizedBox(height: 16),
            _buildConfigBox(
              title: "Port",
              activeValue: _activePort,
              controller: _portController,
              onSave: _handleSavePort,
            ),
          ],
        ),
      ),
    );
  }

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
                style: const TextStyle(
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
              ElevatedButton(
                onPressed: () {
                  onSave(controller.text.trim());
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