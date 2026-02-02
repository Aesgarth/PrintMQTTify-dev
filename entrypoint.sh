#!/bin/bash

##echo "Setting NOFILE limit to 65536"
##ulimit -n 65536

# Copy the custom cupsd.conf file
if [ -f /app/cupsd.conf ]; then
  echo "Copying custom cupsd.conf..."
  cp /app/cupsd.conf /etc/cups/cupsd.conf
  chmod 644 /etc/cups/cupsd.conf
  chown root:lp /etc/cups/cupsd.conf
else
  echo "Custom cupsd.conf not found!"
fi

# Create admin user if it doesn't already exist
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASS=${ADMIN_PASS:-adminpassword}

if ! id -u $ADMIN_USER > /dev/null 2>&1; then
  echo "Creating admin user..."
  adduser --disabled-password --gecos "" $ADMIN_USER
  echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
  usermod -aG lpadmin $ADMIN_USER
else
  echo "Admin user already exists."
fi

# Install custom drivers from the mapped volume
CUSTOM_DRIVER_DIR="/drivers/custom"
if [ -d "$CUSTOM_DRIVER_DIR" ]; then
  echo "Checking for custom drivers in $CUSTOM_DRIVER_DIR..."
  
  # Install .deb files
  for f in "$CUSTOM_DRIVER_DIR"/*.deb; do
    [ -e "$f" ] && echo "Installing $f..." && dpkg -i "$f"
  done

  # Install .tar.gz files
  for f in "$CUSTOM_DRIVER_DIR"/*.tar.gz; do
    if [ -e "$f" ]; then
       echo "Extracting and installing $f..."
       # Extract to a unique temp folder to avoid conflicts
       mkdir -p /tmp/driver_install
       tar -zxvf "$f" -C /tmp/driver_install
       
       # Find the setup.sh regardless of the top-level folder name
       SETUP_PATH=$(find /tmp/driver_install -name "setup.sh" | head -n 1)
       
       if [ -f "$SETUP_PATH" ]; then
          DRIVER_ROOT=$(dirname "$SETUP_PATH")
          echo "Found setup script at $SETUP_PATH. Running..."
          cd "$DRIVER_ROOT" && chmod +x setup.sh && ./setup.sh
       else
          echo "Could not find setup.sh in $f"
       fi
       
       # Clean up
       rm -rf /tmp/driver_install
    fi
  done
fi

# Start Avahi Daemon
echo "Starting Avahi Daemon..."
service avahi-daemon start

# Stop any running CUPS processes
echo "Ensuring no conflicting CUPS processes..."
pkill cupsd || true

# Start CUPS service
echo "Starting CUPS service..."
service cups start
if [ $? -eq 0 ]; then
  echo "CUPS service started successfully."
else
  echo "Failed to start CUPS service."
  exit 1
fi

# Wait for CUPS to initialize
sleep 2

cupsctl --remote-admin --remote-any --share-printers

# Tail the CUPS log in the background
echo "Tailing CUPS logs..."
tail -f /var/log/cups/error_log &

# Start the Flask web control panel
echo "Starting Flask web control panel..."
python3 /app/web_control_panel.py &

# Start the MQTT handler
echo "Starting MQTT handler..."
python3 /app/printer_mqtt_handler.py
if [ $? -ne 0 ]; then
  echo "Failed to start MQTT handler."
  exit 1
fi
