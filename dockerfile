FROM debian:bullseye

# Install necessary packages 
# Added dbus, libfreetype6, and liblcms2-2 to prevent ReportLab crashes
RUN apt-get update && apt-get install -y \
    cups \
    cups-client \
    cups-pdf \
    python3 \
    python3-pip \
    libcupsimage2 \
    avahi-daemon \
    dbus \
    libfreetype6 \
    liblcms2-2 \
    libjpeg62-turbo \
    ssl-cert \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV APP_DIR=/app
RUN mkdir -p $APP_DIR
WORKDIR $APP_DIR

# Copy configs and scripts
COPY configs/cupsd.conf $APP_DIR/cupsd.conf
COPY entrypoint.sh $APP_DIR/entrypoint.sh
COPY app/templates /app/templates

# Ensure permissions are correct
RUN chmod 644 $APP_DIR/cupsd.conf && chmod +x $APP_DIR/entrypoint.sh

# Install Python dependencies
RUN pip3 install paho-mqtt flask reportlab

# Copy application scripts
COPY app/printer_mqtt_handler.py $APP_DIR/printer_mqtt_handler.py
COPY app/web_control_panel.py $APP_DIR/web_control_panel.py

EXPOSE 631 8080

ENTRYPOINT ["/app/entrypoint.sh"]