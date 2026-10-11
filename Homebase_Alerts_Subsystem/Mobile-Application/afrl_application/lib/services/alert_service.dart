/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           alert_service.dart
Author:         Cameron Homer
Date:           10/10/2026
Description:    Setup abstraction for services so swap to WebSocket is easy if we do so
*/

import '../models/alert_data.dart';

abstract class AlertService {
  //Stream<List<AlertData>> get alertDataStream;
  Future<List<AlertData>> getAlerts(String hostIp, String port);
  void dispose();
}