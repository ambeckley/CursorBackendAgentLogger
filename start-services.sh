#!/bin/bash
# .cursor/start-services.sh - Start monitoring services
# Aaron Beckley 2025

echo "Starting monitoring services..."

# Create startup script
sudo tee /usr/local/bin/startup.sh > /dev/null << 'EOF'
#!/bin/bash
LOG_DIR="/var/log/agent"
NETWORK_LOG_FILE="$LOG_DIR/network.log"
COMMAND_LOG_FILE="$LOG_DIR/commands.log"
SYSTEM_LOG_FILE="$LOG_DIR/system.log"
STARTUP_LOG_FILE="$LOG_DIR/startup.log"

log_startup() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp: $1" >> "$STARTUP_LOG_FILE"
}

init_logging() {
    log_startup "Initializing logging system..."
    touch "$NETWORK_LOG_FILE" "$COMMAND_LOG_FILE" "$SYSTEM_LOG_FILE" "$STARTUP_LOG_FILE"
    chmod 666 "$LOG_DIR"/*.log
    log_startup "Logging system initialized"
}

start_network_monitoring() {
    log_startup "Starting network monitoring..."
    /usr/local/bin/network-monitor.sh &
    echo $! > /var/run/network-monitor.pid
    log_startup "Network monitoring started"
}

start_command_logging() {
    log_startup "Starting command logging..."
    /usr/local/bin/command-logger.sh &
    echo $! > /var/run/command-logger.pid
    log_startup "Command logging started"
}

start_system_monitoring() {
    log_startup "Starting system monitoring..."
    /usr/local/bin/system-monitor.sh &
    echo $! > /var/run/system-monitor.pid
    log_startup "System monitoring started"
}

setup_network_restrictions() {
    log_startup "Setting up network restrictions..."
    /usr/local/bin/setup-firewall.sh
    log_startup "Network restrictions configured"
}

start_central_logging() {
    log_startup "Starting central logging..."
    /usr/local/bin/central-logger.sh &
    echo $! > /var/run/central-logger.pid
    log_startup "Central logging started"
}

main() {
    log_startup "Starting Cursor background agent with logging and monitoring..."
    
    init_logging
    setup_network_restrictions
    start_network_monitoring
    start_command_logging
    start_system_monitoring
    start_central_logging
    
    log_startup "All systems initialized successfully"
    exec "$@"
}

main "$@"
EOF

# Make startup script executable
sudo chmod +x /usr/local/bin/startup.sh

# Start the monitoring services
sudo /usr/local/bin/startup.sh &

echo "Monitoring services started successfully!"
echo "Check /var/log/agent/ for log files."
echo "Central logging configured to send to: ${LOG_SERVER:-localhost:8080}"
