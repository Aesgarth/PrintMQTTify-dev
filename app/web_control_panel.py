from flask import Flask, render_template, request, jsonify
import subprocess
import os
import paho.mqtt.publish as publish

app = Flask(__name__)

# Initial Settings
mqtt_broker = os.getenv("MQTT_BROKER", "localhost")
mqtt_topic = os.getenv("MQTT_TOPIC", "printer/commands")
cups_user = os.getenv("ADMIN_USER", "admin")

def get_mqtt_auth():
    u = os.getenv("MQTT_USERNAME")
    p = os.getenv("MQTT_PASSWORD")
    return {'username': u, 'password': p} if u else None

@app.route('/')
def index():
    ha_status = os.getenv("HA_DISCOVERY", "true")
    return render_template('index.html', 
                           mqtt_broker=mqtt_broker, 
                           mqtt_topic=mqtt_topic, 
                           cups_user=cups_user,
                           ha_status=ha_status)

@app.route('/update-settings', methods=['POST'])
def update_settings():
    # In a real app, you'd save these to a file. 
    # For now, we update the runtime and notify the handler.
    global mqtt_broker, mqtt_topic
    mqtt_broker = request.form.get('mqtt_broker', mqtt_broker)
    mqtt_topic = request.form.get('mqtt_topic', mqtt_topic)
    
    ha_enabled = request.form.get('ha_discovery') == 'on'
    msg = "ON" if ha_enabled else "OFF"
    
    try:
        publish.single("printer/discovery/control", payload=msg, 
                       hostname=mqtt_broker, auth=get_mqtt_auth())
        return jsonify({"success": True, "message": "Settings applied!"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})

@app.route('/status')
def status():
    try:
        # Get installed printers
        printers_res = subprocess.check_output(["lpstat", "-p"], text=True)
        printers = printers_res.strip().split("\n") if printers_res else ["No printers installed"]
        
        # Get available drivers (filtered to show relevant info)
        # We use lpinfo -m to list drivers
        drivers_res = subprocess.check_output(["lpinfo", "-m"], text=True)
        # We'll just take the last 20 for the UI or filter for custom ones
        drivers = drivers_res.strip().split("\n")
        
        return jsonify({
            "printers": printers,
            "drivers": drivers[-20:] # Showing recent/limited list for readability
        })
    except Exception as e:
        return jsonify({"error": str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)