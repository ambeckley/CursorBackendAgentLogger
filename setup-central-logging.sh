#!/bin/bash
# .cursor/setup-central-logging.sh - Setup central logging
# Aaron Beckley 2025

echo "Setting up central logging..."

# Set up central logging environment variables
echo "export LOG_SERVER=\"${LOG_SERVER:-example.com:8080}\"" >> /home/agent/.bashrc
echo "export LOG_ENDPOINT=\"${LOG_ENDPOINT:-/api/logs}\"" >> /home/agent/.bashrc

# Create central logging script
sudo tee /usr/local/bin/central-logger.sh > /dev/null << 'EOF'
#!/bin/bash
LOG_SERVER="${LOG_SERVER:-example.com:8080}"
LOG_ENDPOINT="${LOG_ENDPOINT:-/api/logs}"
LOG_INTERVAL=30

send_logs() {
    local log_file="$1"
    local log_type="$2"
    
    if [ -f "$log_file" ]; then
        tail -n 50 "$log_file" | while read line; do
            curl -s -X POST "$LOG_SERVER$LOG_ENDPOINT" \
                -H "Content-Type: application/json" \
                -d "{\"timestamp\":\"$(date -Iseconds)\",\"type\":\"$log_type\",\"message\":\"$line\",\"hostname\":\"$(hostname)\"}" \
                || echo "Failed to send log: $line"
        done
    fi
}

log_central() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "/var/log/agent/central.log"
}

log_central "Starting central logging to $LOG_SERVER"

while true; do
    send_logs "/var/log/agent/network.log" "network"
    send_logs "/var/log/agent/commands.log" "commands"
    send_logs "/var/log/agent/system.log" "system"
    send_logs "/var/log/agent/startup.log" "startup"
    
    sleep $LOG_INTERVAL
done
EOF

# Make central logger script executable
sudo chmod +x /usr/local/bin/central-logger.sh

echo "Central logging configured to send to: ${LOG_SERVER:-example.com:8080}"
echo "Central logging setup completed successfully!"