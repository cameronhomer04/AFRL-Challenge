/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           box_data.dart
Author:         Cameron Homer
Date:           10/12/2026
Description:    Structures a class for dashboard usage
*/

import 'package:flutter/material.dart';

class BoxData {
  final String label;
  final String value;
  final IconData icon;
  final Color boxColor;
  final Color textColor;
  final Color iconColor;

  BoxData({
    required this.label,
    required this.value,
    required this.icon,
    this.boxColor = const Color(0xFF1E1E1E),
    this.textColor = Colors.white60,
    this.iconColor = Colors.greenAccent,
  });
}