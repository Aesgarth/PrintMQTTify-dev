#!/bin/bash

# 1. CUPS Configuration Setup
# Copy the custom cupsd.conf file provided in the repository
if [ -f /app/cupsd.conf ]; then
  echo "Copying custom cupsd.conf..."
  cp /app/cupsd.conf /etc/cups/cupsd.conf
  chmod 644 /etc/cups/cupsd.conf
  chown root:lp /etc/cups/cupsd.conf
else
  echo "Warning: Custom cupsd.conf not found at /app/cupsd.conf"
fi

# 2. User Management
# Create the CUPS admin user using credentials from the .env file
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASS=${ADMIN_PASS:-adminpassword}

if ! id -u "$ADMIN_USER" > /dev/null 2>&1; then
  echo "Creating admin user: $ADMIN_USER"
  adduser --disabled-password --gecos "" "$ADMIN_USER"
  echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
  usermod -aG lpadmin "$ADMIN_USER"
else
  echo "Admin user $ADMIN_USER already exists."
fi

# 3. Universal Driver Installation Logic
# Automatically detect and install drivers dropped into the mapped volume
CUSTOM_DRIVER_DIR="/drivers/custom"
if [ -d "$CUSTOM_DRIVER_DIR" ]; then
  echo "Checking for custom drivers in $CUSTOM_DRIVER_DIR..."
  
  # Install Debian packages (.deb)
  for f in "$CUSTOM_DRIVER_DIR"/*.deb; do
    if [ -e "$f" ]; then
      echo "Installing Debian driver: $f"
      dpkg -i "$f" || apt-get install -f -y
    fi
  done

  # Extract and install Compressed Archives (.tar.gz)
  for f in "$CUSTOM_DRIVER_DIR"/*.tar.gz; do
    if [ -e "$f" ]; then
       echo "Extracting and installing archive: $f"
       mkdir -p /tmp/driver_install
       tar -zxvf "$f" -C /tmp/driver_install
       
       # Search for a setup script anywhere in the extracted folder
       SETUP_PATH=$(find /tmp/driver_install -name "setup.sh" | head -n 1)
       
       if [ -f "$SETUP_PATH" ]; then
          DRIVER_ROOT=$(dirname "$SETUP_PATH")
          echo "Executing setup script at $SETUP_PATH"
          cd "$DRIVER_ROOT" && chmod +x setup.sh && ./setup.sh
       else
          echo "No setup.sh found in $f"
       fi
       rm -rf /tmp/driver_install
    fi
  done

  # 4. Universal Permissions Fixes
  # Thermal printers often fail if CUPS filters don't have strict root ownership
  echo "Applying CUPS filter permission fixes..."
  if [ -d /usr/lib/cups/filter ]; then
    chown -R root:root /usr/lib/cups/filter
    chmod -R 755 /usr/lib/cups/filter
  fi

  # Symlink PPDs to the standard model directory so CUPS lists them in the UI
  find /usr/share/ppd -name "*.ppd" -exec ln -sf {} /usr/share/cups/model/ \; 2>/dev/null || true
fi

# 5. Service Startup (The D-Bus Fix)
# Initialize D-Bus first to prevent Avahi communication errors
echo "Initializing D-Bus system..."
mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid
dbus-daemon --system --fork

echo "Starting Avahi Daemon..."
service avahi-daemon start

echo "Stopping any stale CUPS instances..."
pkill cupsd || true

echo "Starting CUPS service..."
service cups start
if [ $? -eq 0 ]; then
  echo "CUPS service started successfully."
else
  echo "Critical Error: CUPS failed to start."
  exit 1
fi

# 6. Post-Startup Configuration
sleep 2
# Enable remote administration and printer sharing
cupsctl --remote-admin --remote-any --share-printers

# Tail CUPS error logs to the container output for debugging
echo "Monitoring CUPS logs..."
tail -f /var/log/cups/error_log &

# Start the Flask control panel in the background
echo "Starting Web Control Panel..."
python3 /app/web_control_panel.py &

# 7. Start MQTT Handler (Foreground Process)
# This keeps the container running
echo "Starting MQTT Handler..."
exec python3 /app/printer_mqtt_handler.py