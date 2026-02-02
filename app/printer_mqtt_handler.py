import paho.mqtt.client as mqtt
import os
import subprocess
import time
import threading
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import mm
import json

# Read configurations
broker = os.getenv("MQTT_BROKER", "localhost")
username = os.getenv("MQTT_USERNAME")
password = os.getenv("MQTT_PASSWORD")
topic = os.getenv("MQTT_TOPIC", "printer/commands")
availability_topic = "printer/availability"
ha_discovery_enabled = os.getenv("HA_DISCOVERY", "true").lower() == "true"

# Discovery Constants
DISCOVERY_PREFIX = "homeassistant"
DEVICE_ID = "printmqttify_bridge"

def publish_ha_discovery(client):
    """Publishes MQTT Discovery configs for Home Assistant."""
    device_info = {
        "identifiers": [DEVICE_ID],
        "name": "PrintMQTTify",
        "model": "Thermal Printer Bridge",
        "manufacturer": "PrintMQTTify"
    }

    # 1. Status Sensor (Binary or Sensor)
    sensor_config = {
        "name": "Printer Connectivity",
        "state_topic": availability_topic,
        "unique_id": f"{DEVICE_ID}_status",
        "device": device_info,
        "icon": "mdi:printer"
    }
    
    # 2. Text Entity for Notifications
    text_config = {
        "name": "Printer Notification",
        "command_topic": topic,
        "unique_id": f"{DEVICE_ID}_notify",
        "device": device_info,
        "icon": "mdi:message-text-outline"
    }

    client.publish(f"{DISCOVERY_PREFIX}/sensor/{DEVICE_ID}/status/config", json.dumps(sensor_config), retain=True)
    client.publish(f"{DISCOVERY_PREFIX}/text/{DEVICE_ID}/notify/config", json.dumps(text_config), retain=True)
    print("HA Discovery payloads published.")

def remove_ha_discovery(client):
    """Sends empty payloads to remove entities from HA."""
    client.publish(f"{DISCOVERY_PREFIX}/sensor/{DEVICE_ID}/status/config", "", retain=True)
    client.publish(f"{DISCOVERY_PREFIX}/text/{DEVICE_ID}/notify/config", "", retain=True)
    print("HA Discovery payloads cleared.")

def publish_availability(client, interval=60):
    def publish_status():
        while True:
            try:
                result = subprocess.run(["lpstat", "-p"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                status = "online" if "idle" in result.stdout or "is ready" in result.stdout else "offline"
            except Exception:
                status = "offline"
            client.publish(availability_topic, status, qos=1, retain=True)
            time.sleep(interval)

    thread = threading.Thread(target=publish_status, daemon=True)
    thread.start()

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("Connected to MQTT broker!")
        client.subscribe(topic)
        client.subscribe("printer/discovery/control") # Topic for web panel toggle
        publish_availability(client)
        if ha_discovery_enabled:
            publish_ha_discovery(client)
    else:
        print(f"Failed to connect, return code {rc}")

def on_message(client, userdata, msg):
    payload_str = msg.payload.decode()
    
    # Handle internal toggle from web panel
    if msg.topic == "printer/discovery/control":
        if payload_str == "ON":
            publish_ha_discovery(client)
        else:
            remove_ha_discovery(client)
        return

    print(f"Received print request: {payload_str}")
    try:
        # Try to parse as JSON first
        try:
            data = json.loads(payload_str)
            printer_name = data.get("printer_name", os.getenv("DEFAULT_PRINTER", "default"))
            title = data.get("title", "MQTT Notification")
            message = data.get("message", "No message content")
        except json.JSONDecodeError:
            # If not JSON, assume it's a raw string from HA Text Entity
            printer_name = os.getenv("DEFAULT_PRINTER", "default")
            title = "HA Notification"
            message = payload_str

        pdf_path = generate_pdf(title, message)
        if pdf_path:
            send_to_printer(printer_name, pdf_path)

    except Exception as e:
        print(f"Error handling message: {e}")

def generate_pdf(title, message):
    try:
        page_width = 80 * mm
        margin = 5 * mm
        line_height = 12
        lines = message.split('\n')
        calculated_height = margin + (len(lines) + 4) * line_height
        page_height = max(calculated_height, 100 * mm)

        pdf_path = "/tmp/print_job.pdf"
        c = canvas.Canvas(pdf_path, pagesize=(page_width, page_height))
        y = page_height - margin
        
        c.setFont("Helvetica-Bold", 12)
        c.drawString(margin, y, title)
        y -= line_height
        c.line(margin, y, page_width - margin, y)
        y -= line_height
        
        c.setFont("Helvetica", 10)
        for line in lines:
            c.drawString(margin, y, line)
            y -= line_height

        c.save()
        return pdf_path
    except Exception as e:
        print(f"PDF Error: {e}")
        return None

def send_to_printer(printer_name, pdf_path):
    try:
        subprocess.run(["lp", "-d", printer_name, pdf_path], check=True)
        print(f"Sent to {printer_name} successfully.")
    except Exception as e:
        print(f"Printing failed: {e}")

if __name__ == "__main__":
    client = mqtt.Client()
    if username and password:
        client.username_pw_set(username, password)
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, 1883, 60)
    client.loop_forever()