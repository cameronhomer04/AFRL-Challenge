/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           configuration_screen.dart
Author:         Cameron Homer
Date:           10/26/2026
Description:    Handles resetting the server's alert data
*/

import 'package:flutter/material.dart';
import '../services/tcp_service.dart';

class ResetScreen extends StatefulWidget {
  final TcpAlertService tcpService;

  const ResetScreen({
    super.key,
    required this.tcpService,
  });

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  bool _isResetting = false;

  Future<void> _handleReset() async {
    setState(() {
      _isResetting = true;
    });

    await widget.tcpService.sendResetCommand();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Reset command sent to server."),
          backgroundColor: Colors.greenAccent,
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reset System"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.refresh,
              size: 80,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 24),
            const Text(
              "Clear Active Alerts",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Warning:",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                color: Colors.redAccent,
              ),
            ),
            const Text(
              "Sending a reset command will clear all logged threats in MATLAB and return the system to SCANNING status",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 36),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isResetting ? null : _handleReset,
              child: _isResetting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "SEND RESET COMMAND",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}