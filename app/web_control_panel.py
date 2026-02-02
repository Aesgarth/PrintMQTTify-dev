from flask import Flask, render_template, request, jsonify
import subprocess
import os
import paho.mqtt.publish as publish

app = Flask(__name__)

mqtt_broker = os.getenv("MQTT_BROKER", "localhost")
mqtt_auth = None
if os.getenv("MQTT_USERNAME"):
    mqtt_auth = {'username': os.getenv("MQTT_USERNAME"), 'password': os.getenv("MQTT_PASSWORD")}

@app.route('/')
def index():
    # Use a file or environment to track HA state (simplified here)
    ha_status = os.getenv("HA_DISCOVERY", "true")
    return render_template('index.html', mqtt_broker=mqtt_broker, ha_status=ha_status)

@app.route('/toggle-ha', methods=['POST'])
def toggle_ha():
    enabled = request.form.get('enabled') == 'true'
    msg = "ON" if enabled else "OFF"
    try:
        publish.single("printer/discovery/control", payload=msg, 
                       hostname=mqtt_broker, auth=mqtt_auth)
        return jsonify({"success": True, "status": msg})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})

@app.route('/status')
def status():
    try:
        printers = subprocess.check_output(["lpstat", "-p"], text=True)
        return jsonify({"printers": printers.strip().split("\n")})
    except Exception as e:
        return jsonify({"error": str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)