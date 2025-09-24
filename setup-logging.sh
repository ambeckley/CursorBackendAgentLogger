#!/bin/bash
# .cursor/setup-logging.sh - Setup logging system
# Aaron Beckley 2025

echo "Setting up logging system..."

# Create log directories
sudo mkdir -p /var/log/agent
sudo chown -R agent:agent /var/log/agent

# Set up log rotation
sudo tee /etc/logrotate.d/agent-logs > /dev/null << 'LOGROTATE_EOF'
/var/log/agent/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 666 agent agent
}
LOGROTATE_EOF

# Set up command logging for the agent user
echo 'export PROMPT_COMMAND="history -a; echo \"\$(date): \$(whoami)@\$(hostname): \$(pwd): \$(history 1 | sed \"s/^[ ]*[0-9]*[ ]*//\")\" >> /var/log/agent/commands.log"' >> /home/agent/.bashrc

# Create network monitoring script
sudo tee /usr/local/bin/network-monitor.sh > /dev/null << 'NETWORK_EOF'
#!/bin/bash
LOG_FILE="/var/log/agent/network.log"
MONITOR_INTERVAL=5

log_network() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

get_network_stats() {
    ss -tuln | while read line; do
        if [[ "$line" != "State"* ]]; then
            log_network "Connection: $line"
        fi
    done
    
    cat /proc/net/dev | while read line; do
        if [[ "$line" == *":"* ]]; then
            log_network "Interface stats: $line"
        fi
    done
}

monitor_blocked_connections() {
    dmesg | grep "BLOCKED_OUTPUT" | tail -10 | while read line; do
        log_network "Blocked connection: $line"
    done
}

log_network "Starting network monitoring..."

while true; do
    get_network_stats
    monitor_blocked_connections
    
    local conn_count=$(ss -tuln | wc -l)
    log_network "Active connections: $conn_count"
    
    sleep $MONITOR_INTERVAL
done
NETWORK_EOF

# Create command logging script
sudo tee /usr/local/bin/command-logger.sh > /dev/null << 'COMMAND_EOF'
#!/bin/bash
LOG_FILE="/var/log/agent/commands.log"

log_command() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user=$(whoami)
    local hostname=$(hostname)
    local pwd=$(pwd)
    local command="$1"
    local pid=$$
    
    echo "$timestamp: USER=$user HOST=$hostname PWD=$pwd PID=$pid CMD='$command'" >> "$LOG_FILE"
}

monitor_commands() {
    export PROMPT_COMMAND='history -a; echo "$(date): $(whoami)@$(hostname): $(pwd): $(history 1 | sed "s/^[ ]*[0-9]*[ ]*//")" >> '"$LOG_FILE"
    trap 'log_command "$BASH_COMMAND"' DEBUG
}

start_logging() {
    log_command "Starting command logging system"
    monitor_commands
    
    while true; do
        ps aux | while read line; do
            if [[ "$line" != "USER"* ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): PROCESS: $line" >> "$LOG_FILE"
            fi
        done
        sleep 10
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_logging
fi
COMMAND_EOF

# Create enhanced system monitoring script with process and service monitoring
sudo tee /usr/local/bin/system-monitor.sh > /dev/null << 'SYSTEM_EOF'
#!/bin/bash
LOG_FILE="/var/log/agent/system.log"
MONITOR_INTERVAL=30

log_system() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp: $1" >> "$LOG_FILE"
}

monitor_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    log_system "CPU_USAGE: $cpu_usage%"
    
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    log_system "LOAD_AVERAGE: $load_avg"
}

monitor_memory() {
    free -h | while read line; do
        log_system "MEMORY: $line"
    done
}

monitor_disk() {
    df -h | while read line; do
        log_system "DISK: $line"
    done
}

monitor_network() {
    cat /proc/net/dev | while read line; do
        if [[ "$line" == *":"* ]]; then
            log_system "NETWORK_INTERFACE: $line"
        fi
    done
    
    ss -tuln | wc -l | while read count; do
        log_system "NETWORK_CONNECTIONS: $count"
    done
}

monitor_processes() {
    local process_count=$(ps aux | wc -l)
    log_system "PROCESS_COUNT: $process_count"
    
    # Log all running processes
    ps aux | while read line; do
        if [[ "$line" != "USER"* ]]; then
            log_system "PROCESS: $line"
        fi
    done
    
    # Log top processes by CPU and memory
    ps aux --sort=-%cpu | head -10 | while read line; do
        log_system "TOP_CPU_PROCESS: $line"
    done
    
    ps aux --sort=-%mem | head -10 | while read line; do
        log_system "TOP_MEM_PROCESS: $line"
    done
}

monitor_services() {
    # Log running systemd services
    systemctl list-units --type=service --state=running 2>/dev/null | while read line; do
        if [[ "$line" != "UNIT"* ]] && [[ -n "$line" ]]; then
            log_system "RUNNING_SERVICE: $line"
        fi
    done
    
    # Log failed services
    systemctl list-units --type=service --state=failed 2>/dev/null | while read line; do
        if [[ "$line" != "UNIT"* ]] && [[ -n "$line" ]]; then
            log_system "FAILED_SERVICE: $line"
        fi
    done
    
    # Log listening ports and their services
    netstat -tuln | while read line; do
        if [[ "$line" != "Active"* ]] && [[ -n "$line" ]]; then
            log_system "LISTENING_PORT: $line"
        fi
    done
    
    # Log Docker containers if Docker is running
    if command -v docker >/dev/null 2>&1; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while read line; do
            if [[ "$line" != "NAMES"* ]] && [[ -n "$line" ]]; then
                log_system "DOCKER_CONTAINER: $line"
            fi
        done
    fi
    
    # Log network services
    ss -tuln | while read line; do
        if [[ "$line" != "State"* ]]; then
            log_system "NETWORK_SERVICE: $line"
        fi
    done
}

start_monitoring() {
    log_system "Starting enhanced system monitoring..."
    
    while true; do
        log_system "=== System Monitoring Cycle ==="
        monitor_cpu
        monitor_memory
        monitor_disk
        monitor_network
        monitor_processes
        monitor_services
        log_system "=== End Monitoring Cycle ==="
        sleep $MONITOR_INTERVAL
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_monitoring
fi
SYSTEM_EOF

# Make scripts executable
sudo chmod +x /usr/local/bin/network-monitor.sh
sudo chmod +x /usr/local/bin/command-logger.sh
sudo chmod +x /usr/local/bin/system-monitor.sh

echo "Enhanced logging system configured successfully!"
