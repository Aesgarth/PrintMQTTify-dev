import paho.mqtt.client as mqtt
import os
import subprocess
import time
import threading
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import mm
import json
import re

# Read configurations
broker = os.getenv("MQTT_BROKER", "localhost")
username = os.getenv("MQTT_USERNAME")
password = os.getenv("MQTT_PASSWORD")
topic = os.getenv("MQTT_TOPIC", "printer/commands")
ha_discovery_enabled = os.getenv("HA_DISCOVERY", "true").lower() == "true"

# Discovery Constants
DISCOVERY_PREFIX = "homeassistant"
DEVICE_ID = "printmqttify_bridge"

def get_installed_printers():
    """Parses lpstat to get a list of printer names and their status."""
    printers = []
    try:
        result = subprocess.run(["lpstat", "-p"], stdout=subprocess.PIPE, text=True)
        # Regex to find printer name and status
        matches = re.findall(r"printer\s+(.+?)\s+(is\s+idle|is\s+disabled|now\s+printing)", result.stdout)
        for name, state in matches:
            status = "online" if "idle" in state or "printing" in state else "offline"
            printers.append({"name": name, "status": status})
    except Exception as e:
        print(f"Error parsing printers: {e}")
    return printers

def publish_ha_discovery(client):
    """Publishes Discovery configs for the bridge and all current printers."""
    device_info = {
        "identifiers": [DEVICE_ID],
        "name": "PrintMQTTify",
        "model": "Thermal Printer Bridge",
        "manufacturer": "PrintMQTTify"
    }

    # 1. Global Service Status (Container is running)
    bridge_config = {
        "name": "PrintMQTTify Service",
        "state_topic": "printer/service/status",
        "unique_id": f"{DEVICE_ID}_service",
        "device": device_info,
        "icon": "mdi:server-network"
    }
    client.publish(f"{DISCOVERY_PREFIX}/sensor/{DEVICE_ID}/service/config", json.dumps(bridge_config), retain=True)
    client.publish("printer/service/status", "online", retain=True)

    # 2. Text Entity for Notifications
    text_config = {
        "name": "Send Message to Printer",
        "command_topic": topic,
        "unique_id": f"{DEVICE_ID}_notify",
        "device": device_info,
        "icon": "mdi:message-text-outline"
    }
    client.publish(f"{DISCOVERY_PREFIX}/text/{DEVICE_ID}/notify/config", json.dumps(text_config), retain=True)

    # 3. Dynamic Printer Sensors
    for printer in get_installed_printers():
        safe_name = printer['name'].replace(" ", "_").lower()
        p_config = {
            "name": f"Printer {printer['name']}",
            "state_topic": f"printer/{safe_name}/status",
            "unique_id": f"{DEVICE_ID}_{safe_name}_status",
            "device": device_info,
            "icon": "mdi:printer"
        }
        client.publish(f"{DISCOVERY_PREFIX}/sensor/{DEVICE_ID}/{safe_name}/config", json.dumps(p_config), retain=True)
    
    print("HA Discovery payloads published.")

def remove_ha_discovery(client):
    """Sends empty payloads to remove all potential entities from HA."""
    client.publish(f"{DISCOVERY_PREFIX}/sensor/{DEVICE_ID}/service/config", "", retain=True)
    client.publish(f"{DISCOVERY_PREFIX}/text/{DEVICE_ID}/notify/config", "", retain=True)
    # Note: Specific printer entities are harder to clear without a list, 
    # but clearing the device ID helps.
    print("HA Discovery payloads cleared.")

def monitor_printers(client, interval=30):
    """Periodically checks and updates status for every printer."""
    def run():
        while True:
            printers = get_installed_printers()
            if not printers:
                # If no printers installed, we stay 'online' as a service but have no printer entities
                client.publish("printer/service/status", "online", retain=True)
            for p in printers:
                safe_name = p['name'].replace(" ", "_").lower()
                client.publish(f"printer/{safe_name}/status", p['status'], qos=1, retain=True)
            time.sleep(interval)

    thread = threading.Thread(target=run, daemon=True)
    thread.start()

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("Connected to MQTT broker!")
        client.subscribe(topic)
        client.subscribe("printer/discovery/control")
        monitor_printers(client)
        if ha_discovery_enabled:
            publish_ha_discovery(client)
    else:
        print(f"Failed to connect: {rc}")

def on_message(client, userdata, msg):
    payload_str = msg.payload.decode()
    if msg.topic == "printer/discovery/control":
        if payload_str == "ON":
            publish_ha_discovery(client)
        else:
            remove_ha_discovery(client)
        return

    try:
        try:
            data = json.loads(payload_str)
            p_name = data.get("printer_name")
            title = data.get("title", "MQTT Notification")
            msg_text = data.get("message", "No content")
        except:
            # Simple text from HA
            p_name = None
            title = "HA Notification"
            msg_text = payload_str

        # If no printer specified, try to find the first idle one
        if not p_name:
            available = get_installed_printers()
            p_name = available[0]['name'] if available else None

        if p_name:
            pdf = generate_pdf(title, msg_text)
            if pdf:
                subprocess.run(["lp", "-d", p_name, pdf], check=True)
    except Exception as e:
        print(f"Error: {e}")

def generate_pdf(title, message):
    try:
        page_width = 80 * mm
        margin = 5 * mm
        line_height = 12
        lines = message.split('\n')
        page_height = max((len(lines) + 5) * line_height, 60 * mm)
        path = "/tmp/print_job.pdf"
        c = canvas.Canvas(path, pagesize=(page_width, page_height))
        y = page_height - margin
        c.setFont("Helvetica-Bold", 12)
        c.drawString(margin, y, title)
        y -= line_height
        c.line(margin, y, page_width-margin, y)
        y -= line_height
        c.setFont("Helvetica", 10)
        for line in lines:
            c.drawString(margin, y, line)
            y -= line_height
        c.save()
        return path
    except:
        return None

if __name__ == "__main__":
    client = mqtt.Client()
    if username and password:
        client.username_pw_set(username, password)
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, 1883, 60)
    client.loop_forever()