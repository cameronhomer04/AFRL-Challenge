'''
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           mock_server.py
Author:         Cameron Homer
Date:           10/05/2026
Description:    This is an AI Generated REST Service purelly for the purpose of testing the mobile app's rest capabilities
'''

from flask import Flask, jsonify
import random

app = Flask(__name__)

# Toggle this variable to manually test SCANNING vs ALERT mode
SIMULATE_ALERT = True

@app.route('/api/alert/get', methods=['GET'])
def get_alerts():
    if SIMULATE_ALERT:
        return jsonify([
            {
                "status": "ALERT",
                "center_freq": 2450.0,
                "modulation": "64QAM",
                "node": 1
            },
            {
                "status": "ALERT",
                "center_freq": 70,
                "modulation": "FM",
                "node": 2
            },
            {
                "status": "ALERT",
                "center_freq": 5600,
                "modulation": "QPSK",
                "node": 3
            },
            {
                "status": "SCANNING",
                "center_freq": 0.0,
                "modulation": "NONE",
                "node": 0
            }
        ])
    else:
        return jsonify([
            {
                "status": "SCANNING",
                "center_freq": 0.0,
                "modulation": "NONE",
                "node": 0
            }
        ])

if __name__ == '__main__':
    # host='0.0.0.0' allows external devices/emulators to connect
    app.run(host='0.0.0.0', port=5000, debug=True)