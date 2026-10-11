/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           alert_data.dart
Author:         Cameron Homer
Date:           10/05/2026
Description:    Structures the JSON mapping of alert data
*/

class AlertData {
  final String status;
  final double centerFreq;
  final String modulationType;
  final int sdrNode;

  AlertData({
    required this.status,
    required this.centerFreq,
    required this.modulationType,
    required this.sdrNode
  });

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is AlertData &&
      status == other.status &&
      centerFreq == other.centerFreq &&
      modulationType == other.modulationType &&
      sdrNode == other.sdrNode;
  
  @override
  int get hashCode =>
    status.hashCode ^
    centerFreq.hashCode ^
    modulationType.hashCode ^
    sdrNode.hashCode;

  bool get alertStatus => status == 'ALERT';

  factory AlertData.fromJson(Map<String, dynamic> json) {
    return AlertData(
      status: json['status'] ?? "SCANNING",
      centerFreq: (json['center_freq'] as num?)?.toDouble() ?? 0.0,
      modulationType: json['modulation'] ?? 'NONE',
      sdrNode: json['node'] ?? 0,
    );
  }
}