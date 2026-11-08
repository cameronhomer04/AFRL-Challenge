/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           configuration_screen.dart
Author:         Cameron Homer
Date:           10/26/2026
Description:    Handles resetting the server's alert data
*/

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key});

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isResetting = false;
  bool _hasPasswordConfigured = false;
  String _savedPassword = "";

  @override
  void initState() {
    super.initState();
    _loadPassword();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final password = prefs.getString('reset_password') ?? "";
    if (mounted){
      setState(() {
        _savedPassword = password;
        _hasPasswordConfigured = password.isNotEmpty;
      });
    }
  }

  Future<void> _handleReset() async {
    final enteredPassword = _passwordController.text.trim();
    if(!_hasPasswordConfigured) {
      _showSnackBar("Please set a password in the Server Settings", Colors.redAccent);
      return;
    }
    if (enteredPassword.isEmpty) {
      _showSnackBar("Please enter the authorization password", Colors.redAccent);
      return;
    }
    else if (enteredPassword != _savedPassword) {
      _showSnackBar("Incorrect authorization password", Colors.redAccent);
      return;
    }

    setState(() {
      _isResetting = true;
    });
    FlutterForegroundTask.sendDataToTask('RESET');
    if (mounted) {
      _showSnackBar("Reset command sent to server", Colors.greenAccent);
      Navigator.pop(context);
    }
  }

  void _showSnackBar(String message, Color boxColor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: boxColor,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      );
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
      body: SingleChildScrollView(
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
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12.0),
              ),
              child : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: "Enter Authorization Password",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF2C2C2C),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 28),
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
          ],
        ),
      ),
    );
  }
}