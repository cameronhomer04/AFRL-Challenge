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
  final bool checksumValid;
  final String receivedTime;

  AlertData({
    required this.status,
    required this.centerFreq,
    required this.modulationType,
    required this.sdrNode,
    required this.checksumValid,
    this.receivedTime = "",
  });

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is AlertData &&
      status == other.status &&
      centerFreq == other.centerFreq &&
      modulationType == other.modulationType &&
      sdrNode == other.sdrNode &&
      checksumValid == other.checksumValid &&
      receivedTime == other.receivedTime;

  @override
  int get hashCode =>
    status.hashCode ^
    centerFreq.hashCode ^
    modulationType.hashCode ^
    sdrNode.hashCode ^
    checksumValid.hashCode ^
    receivedTime.hashCode;

  bool get alertStatus => status == 'ALERT';

  factory AlertData.fromJson(Map<String, dynamic> json) {
    return AlertData(
      status: json['status'] ?? "SCANNING",
      centerFreq: (json['center_freq'] as num?)?.toDouble() ?? 0.0,
      modulationType: json['modulation'] ?? 'NONE',
      sdrNode: json['node'] ?? 0,
      checksumValid: json['checksum_valid'] ?? true,
      receivedTime: json['received_time'] ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'center_freq': centerFreq,
      'modulation': modulationType,
      'node': sdrNode,
      'checksum_valid': checksumValid,
      'received_time': receivedTime,
    };
  }
}