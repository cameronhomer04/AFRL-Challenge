/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           configuration_screen.dart
Author:         Cameron Homer
Date:           10/17/2026
Description:    Handles the user configuration of IP Address and Port
*/

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  bool _hasExistingPassword = false;

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
    _currentPasswordController = TextEditingController(text: "");
    _newPasswordController = TextEditingController(text: "");
    _checkExistingPassword();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedPassword = prefs.getString('reset_password');
    if (mounted){
      setState(() {
        _hasExistingPassword = savedPassword != null && savedPassword.isNotEmpty;
      });
    }
  }

  void _handleSaveIp(String newIp) async {
    if (newIp.trim().isEmpty) {
      _showSnackBar("IP address cannot be empty", Colors.redAccent);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', newIp.trim());
    await prefs.setString('server_port', _activePort);

    setState(() {
      _activeIp = newIp.trim();
    });
    widget.onSave(_activeIp, _activePort);
    _showSnackBar("Host IP updated to $_activeIp", Colors.greenAccent);
  }

  void _handleSavePort(String newPort) async {
    if (newPort.trim().isEmpty) {
      _showSnackBar("Port cannot be empty", Colors.redAccent);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', _activeIp);
    await prefs.setString('server_port', newPort.trim());

    setState(() {
      _activePort = newPort.trim();
    });
    widget.onSave(_activeIp, _activePort);
    _showSnackBar("Port updated to $_activePort", Colors.greenAccent);
  }

  void _handleSavePassword() async {
    final newPass = _newPasswordController.text.trim();
    if (newPass.isEmpty) {
      _showSnackBar("Password cannot be empty", Colors.redAccent);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final savedPass = prefs.getString('reset_password') ?? '';
    if (_hasExistingPassword) {
      final currentPass = _currentPasswordController.text.trim();
      if (currentPass != savedPass) {
        _showSnackBar("Current password does not match", Colors.redAccent);
        return;
      }
    }
    await prefs.setString('reset_password', newPass);
    _currentPasswordController.clear();
    _newPasswordController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _hasExistingPassword = true;
    });
    _showSnackBar("Reset password successfully saved", Colors.greenAccent);
  }

  void _showSnackBar(String message, Color boxColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        backgroundColor: boxColor,
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
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildConfigBox(
                title: "Host IP Address",
                activeValue: _activeIp,
                icon: Icons.dns_outlined,
                controller: _ipController,
                onSave: _handleSaveIp,
              ),
              const SizedBox(height: 16),
              _buildConfigBox(
                title: "Port",
                activeValue: _activePort,
                icon: Icons.numbers_outlined,
                controller: _portController,
                onSave: _handleSavePort,
              ),
              const SizedBox(height: 16),
              _buildPasswordConfigBox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigBox({required String title, required String activeValue, required IconData icon, required TextEditingController controller, required ValueChanged<String> onSave,}) {
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
                title,
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
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: "Enter $title",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF2C2C2C),
              prefixIcon: Icon(icon, color: Colors.white54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            style: const TextStyle(color: Colors.white),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                onSave(controller.text.trim());
                controller.clear();
                FocusScope.of(context).unfocus();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              child: Text("Update $title", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordConfigBox() {
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
                "Reset Authorization Password",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _hasExistingPassword ? "Status: SET" : "Status: NOT SET",
                style: TextStyle(
                  color: _hasExistingPassword ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hasExistingPassword) ...[
            TextField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: "Enter Current Password",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                prefixIcon: const Icon(Icons.lock_open, color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: _hasExistingPassword ? "Enter New Password" : "Set System Password",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF2C2C2C),
              prefixIcon: const Icon(Icons.password_outlined, color: Colors.white54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleSavePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              child: Text(
                _hasExistingPassword ? "Update Password" : "Save Password",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}