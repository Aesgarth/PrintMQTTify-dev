PrintMQTTifyPrintMQTTify is a Docker-based solution that bridges MQTT messages to a CUPS printer, allowing you to print messages from your MQTT broker seamlessly. This is particularly useful in smart home setups for automating printing tasks, such as printing shopping lists or event reminders directly from Home Assistant.FeaturesCUPS Integration: Provides a fully functional CUPS server capable of managing multiple printers.MQTT Print Jobs: Listens for MQTT messages to process print jobs efficiently.USB Printer Support: Compatible with USB printers and supports custom drivers.Virtual PDF Printing: Includes pre-configured PDF printers (PDFP and PDFP-A) for testing logic without wasting paper.Web-Based Control Panel: Includes an optional web interface for managing settings and monitoring.PrerequisitesDocker & Docker Compose: Ensure both are installed and running on your system.MQTT Broker: A working broker (e.g., Mosquitto) is required. Note the broker's IP address, username, and password.USB Printer Identification: Use lsusb and dmesg | grep usb to locate the device path of your printer (e.g., /dev/usb/lp0).Installation & Setup1. Build and RunUpdate your docker-compose.yml to include a volume for your virtual printed files:version: '3.8'

services:
  printmqttify:
    image: printmqttify
    container_name: printmqttify_container
    privileged: true
    ports:
      - "631:631"
      - "8080:8080"
    devices:
      - "/dev/usb/lp0:/dev/usb/lp0"
    volumes:
      - ./printed_pdfs:/var/spool/cups-pdf/root  # Maps virtual prints to your host
    environment:
      - MQTT_BROKER=<your-mqtt-broker-ip>
      - MQTT_USERNAME=<your-mqtt-username>
      - MQTT_PASSWORD=<your-mqtt-password>
      - MQTT_TOPIC=printer/commands
      - ADMIN_USER=admin
      - ADMIN_PASS=adminpassword
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
Build and start the container:docker-compose up -d --build
2. Access the CUPS Web InterfaceNavigate to http://<host-ip>:631 in your browser.[!IMPORTANT]HTTPS/SSL Note: If you encounter the error Unable to encrypt connection: Unable to create server credentials, ensure that DefaultEncryption Never is set in your configs/cupsd.conf file. This allows administrative actions over standard HTTP (port 631), which is recommended for private local networks where SSL certificates are not pre-configured.Verification & Testing1. Test with the Virtual PDF PrinterYou can verify the entire MQTT-to-CUPS pipeline without using a physical printer:Send a Test Message: Publish an MQTT payload to your topic with "printer_name": "PDFP".Check the Output: The generated PDF will appear in your mapped ./printed_pdfs folder on your host machine.Internal Verification: To check if a file was created inside the container without mapping a volume, run:docker exec printmqttify_container ls -R /var/spool/cups-pdf/root/
2. Verify with Home AssistantGo to Developer Tools > Services in Home Assistant and use the mqtt.publish service:service: mqtt.publish
data:
  topic: "printer/commands"
  payload: '{"printer_name": "PDFP", "message": "Test Shopping List:\n- Milk\n- Bread\n- Eggs"}'
TroubleshootingSSL Connection Failed: If the CUPS logs show "Unable to create server credentials," access the interface via http:// instead of https:// and ensure mandatory encryption is disabled in cupsd.conf.D-Bus/Avahi Errors: The container handles D-Bus initialization automatically. If you see Avahi errors, check that the host's Avahi service isn't conflicting or that the container has sufficient privileges.Container Logs: Monitor the real-time CUPS and application logs:docker logs -f printmqttify_container
CustomizationOrientation (Portrait vs. Landscape)By default, the system forces "portrait" orientation for short lists to ensure vertical alignment. To allow "landscape" (horizontal) orientation for short content, edit app/printer_mqtt_handler.py:Locate the line: page_height = max(calculated_height, page_width + 1)Change it to: page_height = calculated_heightRebuild the image: docker-compose up -d --buildLicenseThis project is licensed under the Creative Commons Zero v1.0 Universal (CC0 1.0) License.
