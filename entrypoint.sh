#!/bin/bash

# Ensure we are in the correct directory for ReportLab startup
cd /app

# 1. CUPS Configuration Setup
if [ -f /app/cupsd.conf ]; then
  echo "Copying custom cupsd.conf..."
  cp /app/cupsd.conf /etc/cups/cupsd.conf
  chmod 644 /etc/cups/cupsd.conf
  chown root:lp /etc/cups/cupsd.conf
fi

# 2. User Management
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASS=${ADMIN_PASS:-adminpassword}
if ! id -u "$ADMIN_USER" > /dev/null 2>&1; then
  echo "Creating admin user: $ADMIN_USER"
  adduser --disabled-password --gecos "" "$ADMIN_USER"
  echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
  usermod -aG lpadmin "$ADMIN_USER"
fi

# 3. Universal Driver Installation Logic
CUSTOM_DRIVER_DIR="/drivers/custom"
if [ -d "$CUSTOM_DRIVER_DIR" ]; then
  echo "Checking for custom drivers in $CUSTOM_DRIVER_DIR..."
  
  for f in "$CUSTOM_DRIVER_DIR"/*.deb; do
    if [ -e "$f" ]; then
      echo "Installing Debian driver: $f"
      dpkg -i "$f" || apt-get install -f -y
    fi
  done

  for f in "$CUSTOM_DRIVER_DIR"/*.tar.gz; do
    if [ -e "$f" ]; then
       echo "Extracting and installing archive: $f"
       mkdir -p /tmp/driver_install
       tar -zxvf "$f" -C /tmp/driver_install
       SETUP_PATH=$(find /tmp/driver_install -name "setup.sh" | head -n 1)
       if [ -f "$SETUP_PATH" ]; then
          DRIVER_ROOT=$(dirname "$SETUP_PATH")
          echo "Executing setup script at $SETUP_PATH"
          cd "$DRIVER_ROOT" && chmod +x setup.sh && ./setup.sh
          cd /app # Ensure return to application directory
       fi
       rm -rf /tmp/driver_install
    fi
  done

  # 4. Universal Permissions Fixes
  echo "Applying universal CUPS filter and PPD fixes..."
  if [ -d /usr/lib/cups/filter ]; then
    chown -R root:root /usr/lib/cups/filter
    chmod -R 755 /usr/lib/cups/filter
  fi
  find /usr/share/ppd -name "*.ppd" -exec ln -sf {} /usr/share/cups/model/ \; 2>/dev/null || true
fi

# 5. Service Startup (Fixes Avahi communication error)
echo "Initializing D-Bus system..."
mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid
dbus-daemon --system --fork

echo "Starting Avahi Daemon..."
service avahi-daemon start

echo "Stopping any stale CUPS instances..."
pkill cupsd || true

mkdir -p /etc/cups/ssl
chmod 700 /etc/cups/ssl

if [ ! -f /etc/cups/ssl/server.crt ]; then
    make-ssl-cert generate-default-snakeoil --force-overwrite
    cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/cups/ssl/localhost.crt
    cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/cups/ssl/localhost.key
    chown root:lp /etc/cups/ssl/localhost.key
    chmod 600 /etc/cups/ssl/localhost.key
fi

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
# Ensure the log file exists so 'tail' doesn't fail
mkdir -p /var/log/cups
touch /var/log/cups/error_log

# Apply admin settings via cupsctl
cupsctl --remote-admin --remote-any --share-printers

# 7. Start Applications
echo "Monitoring CUPS logs..."
tail -f /var/log/cups/error_log &

echo "Starting Web Control Panel..."
python3 /app/web_control_panel.py &

echo "Starting MQTT Handler..."
# exec replaces the shell process to handle signals and CWD correctly
exec python3 /app/printer_mqtt_handler.py