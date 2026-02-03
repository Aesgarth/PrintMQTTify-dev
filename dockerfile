# Base image
FROM debian:bullseye

# Install necessary packages including DBUS and ReportLab dependencies
RUN apt-get update && apt-get install -y \
    cups \
    cups-pdf \
    cups-client \
    python3 \
    python3-pip \
    libcupsimage2 \
    avahi-daemon \
    dbus \
    libfreetype6 \
    liblcms2-2 \
    libjpeg62-turbo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV APP_DIR=/app
# Create the directory explicitly before setting WORKDIR
RUN mkdir -p $APP_DIR
WORKDIR $APP_DIR

# Copy configurations and scripts
COPY configs/cupsd.conf $APP_DIR/cupsd.conf
COPY entrypoint.sh $APP_DIR/entrypoint.sh
COPY app/templates /app/templates

# Ensure permissions
RUN chmod 644 $APP_DIR/cupsd.conf && chmod +x $APP_DIR/entrypoint.sh

# Install Python dependencies
RUN pip3 install paho-mqtt flask reportlab

# Copy application scripts
COPY app/printer_mqtt_handler.py $APP_DIR/printer_mqtt_handler.py
COPY app/web_control_panel.py $APP_DIR/web_control_panel.py

# Expose the CUPS web interface and Flask port
EXPOSE 631 8080

ENTRYPOINT ["/app/entrypoint.sh"]