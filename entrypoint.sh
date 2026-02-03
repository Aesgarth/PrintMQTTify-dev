#!/bin/bash

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
       mkdir -p /tmp/driver_install
       tar -zxvf "$f" -C /tmp/driver_install
       SETUP_PATH=$(find /tmp/driver_install -name "setup.sh" | head -n 1)
       
       if [ -f "$SETUP_PATH" ]; then
          DRIVER_ROOT=$(dirname "$SETUP_PATH")
          echo "Found setup script at $SETUP_PATH. Running..."
          cd "$DRIVER_ROOT" && chmod +x setup.sh && ./setup.sh
       else
          echo "Could not find setup.sh in $f"
       fi
       rm -rf /tmp/driver_install
    fi
  done

  # --- UNIVERSAL REGISTRATION FIXES ---
  echo "Applying universal CUPS filter and PPD fixes..."
  # Ensure all filters are owned by root and executable
  if [ -d /usr/lib/cups/filter ]; then
    chown -R root:root /usr/lib/cups/filter
    chmod -R 755 /usr/lib/cups/filter
  fi

  # Symlink any newly installed PPDs to the main CUPS model directory
  # This helps CUPS "see" drivers that install to /usr/share/ppd/ instead of /usr/share/cups/model/
  find /usr/share/ppd -name "*.ppd" -exec ln -sf {} /usr/share/cups/model/ \; 2>/dev/null || true
fi

# Start Services
echo "Starting Avahi Daemon..."
service avahi-daemon start

echo "Ensuring no conflicting CUPS processes..."
pkill cupsd || true

echo "Starting CUPS service..."
service cups start
if [ $? -eq 0 ]; then
  echo "CUPS service started successfully."
else
  echo "Failed to start CUPS service."
  exit 1
fi

sleep 2
cupsctl --remote-admin --remote-any --share-printers

echo "Tailing CUPS logs..."
tail -f /var/log/cups/error_log &

echo "Starting Flask web control panel..."
python3 /app/web_control_panel.py &

echo "Starting MQTT handler..."
python3 /app/printer_mqtt_handler.py
if [ $? -ne 0 ]; then
  echo "Failed to start MQTT handler."
  exit 1
fi