/*
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           rest_service.dart
Author:         Cameron Homer
Date:           10/10/2026
Description:    Service that interfaces with our RESTful API
*/

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/alert_data.dart';
import "alert_service.dart";

class RestAlertService implements AlertService{
    // Note: we should only care about GET requests on the app side, NOT POST or DELETE requests
    @override
    Future<List<AlertData>> getAlerts(String hostIp, String port) async{
        final String baseUrl = "http://$hostIp:$port/api/alert";
        try{
            final response = await http.get(Uri.parse('$baseUrl/get'));
            // Only care about the JSON message if we properly received it
            if(response.statusCode == 200){
                var data = jsonDecode(response.body) as List<dynamic>;
                List<AlertData> dataList = data.map((data) => AlertData.fromJson(data)).toList();
                return dataList;
            }
        }
        catch(err){
            //print('Http Get Error: $err');
        }
        return [];
    }

    @override
    void dispose(){
        // May need a cleanup function, unsure for now
    }
}