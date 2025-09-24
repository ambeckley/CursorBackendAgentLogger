# Cursor Background Agent Logging System

A comprehensive logging and monitoring system for Cursor background agents with network restrictions and external log forwarding.

## File Structure & Purpose

### Core Configuration
- **`.cursor/Dockerfile`** - Container setup with essential monitoring tools (iptables, ss, netstat, ps, systemctl, curl, htop)
- **`.cursor/environment.json`** - Cursor agent configuration defining install sequence and terminal setup
- **`.cursor/allowlist.txt`** - Network allowlist template containing domains/IPs the agent can access

### Installation Scripts
- **`.cursor/setup-logging.sh`** - Creates monitoring scripts (network-monitor.sh, command-logger.sh, system-monitor.sh) and configures log rotation
- **`.cursor/setup-network.sh`** - Creates firewall script (setup-firewall.sh) and configures iptables rules to block all egress except allowlisted domains
- **`.cursor/setup-central-logging.sh`** - Creates central-logger.sh script and configures external log forwarding to LOG_SERVER
- **`.cursor/start-services.sh`** - Creates startup.sh script and launches all monitoring services in background

## How It Works

### 1. Container Build (Dockerfile)
Installs essential tools for monitoring:
- iptables/netfilter-persistent (firewall management)
- ss/netstat (network connection monitoring)
- ps/systemctl (process and service monitoring)
- curl (HTTP requests for external logging)
- htop (system resource monitoring)
- lsof (file and network descriptor monitoring)

### 2. Agent Startup Flow
```
1. setup-logging.sh    → Creates monitoring scripts and log rotation
2. setup-network.sh    → Sets up firewall rules and network restrictions
3. setup-central-logging.sh → Configures external logging
4. start-services.sh   → Launches all monitoring services
```

### 3. Runtime Monitoring
- **Network Monitor** - Tracks connections and blocked attempts every 5 seconds
- **Command Logger** - Logs all terminal commands with full context
- **System Monitor** - Monitors CPU, memory, processes, services every 30 seconds
- **Central Logger** - Sends logs to external server every 30 seconds

## Detailed Logging Implementation

### Network Monitoring (network-monitor.sh)
**How it works**: Uses `ss -tuln` to get active connections, `cat /proc/net/dev` for interface stats, `dmesg` for blocked connections
**Frequency**: Every 5 seconds
**Code example**:
```bash
get_network_stats() {
    ss -tuln | while read line; do
        if [[ "$line" != "State"* ]]; then
            log_network "Connection: $line"
        fi
    done
}
```

### Command Logging (command-logger.sh)
**How it works**: Uses bash PROMPT_COMMAND and DEBUG trap to capture every command with user, hostname, working directory, PID
**Frequency**: Real-time on every command execution
**Code example**:
```bash
monitor_commands() {
    export PROMPT_COMMAND='history -a; echo "$(date): $(whoami)@$(hostname): $(pwd): $(history 1 | sed "s/^[ ]*[0-9]*[ ]*//")" >> '"$LOG_FILE"
    trap 'log_command "$BASH_COMMAND"' DEBUG
}
```

### System Monitoring (system-monitor.sh)
**How it works**: Uses `top -bn1` for CPU, `free -h` for memory, `df -h` for disk, `ps aux` for processes, `systemctl` for services
**Frequency**: Every 30 seconds
**Code example**:
```bash
monitor_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    log_system "CPU_USAGE: $cpu_usage%"
}
```

### Central Logging (central-logger.sh)
**How it works**: Uses `curl` to POST JSON logs to external server, processes last 50 lines of each log file
**Frequency**: Every 30 seconds
**Code example**:
```bash
send_logs() {
    local log_file="$1"
    local log_type="$2"
    
    if [ -f "$log_file" ]; then
        tail -n 50 "$log_file" | while read line; do
            curl -s -X POST "$LOG_SERVER$LOG_ENDPOINT" \
                -H "Content-Type: application/json" \
                -d "{\"timestamp\":\"$(date -Iseconds)\",\"type\":\"$log_type\",\"message\":\"$line\",\"hostname\":\"$(hostname)\"}"
        done
    fi
}
```

## Log Files & Output Examples

### Network Logs (`/var/log/agent/network.log`)
**Content**: Active connections, interface statistics, blocked connection attempts, connection counts
**Format**: Timestamp + connection details
```
2024-01-15 10:30:15: Connection: tcp 0.0.0.0:22 0.0.0.0:* LISTEN
2024-01-15 10:30:15: Interface stats: eth0: 1234 5678 0 0 0 0 0 0 0 0 0 0 0 0
2024-01-15 10:30:20: Active connections: 5
2024-01-15 10:30:25: Blocked connection: BLOCKED_OUTPUT: IN= OUT=eth0 SRC=10.0.0.1 DST=192.168.1.1
```

### Command Logs (`/var/log/agent/commands.log`)
**Content**: Every terminal command with user, hostname, working directory, process ID, full command
**Format**: Timestamp + user context + command
```
2024-01-15 10:30:15: USER=agent HOST=agent-container PWD=/home/agent PID=1234 CMD='ls -la'
2024-01-15 10:30:20: USER=agent HOST=agent-container PWD=/home/agent PID=1235 CMD='git clone https://github.com/user/repo.git'
2024-01-15 10:30:25: PROCESS: agent 1234 0.0 0.1 12345 6789 ? S 10:30 0:00 bash
```

### System Logs (`/var/log/agent/system.log`)
**Content**: CPU usage, memory usage, disk usage, process counts, running services, top processes
**Format**: Timestamp + metric type + value
```
2024-01-15 10:30:15: CPU_USAGE: 15.2%
2024-01-15 10:30:15: LOAD_AVERAGE: 0.45, 0.32, 0.28
2024-01-15 10:30:15: MEMORY: Mem: 1.2G 456M 789M 123M 234M 567M
2024-01-15 10:30:15: DISK: /dev/sda1 20G 5.2G 14G 28% /
2024-01-15 10:30:15: PROCESS_COUNT: 45
2024-01-15 10:30:15: RUNNING_SERVICE: ssh.service loaded active running
2024-01-15 10:30:15: TOP_CPU_PROCESS: agent 1234 0.1 0.2 12345 6789 ? S 10:30 0:00 bash
```

### Central Logs (`/var/log/agent/central.log`)
**Content**: External logging status, send attempts, connection status
**Format**: Timestamp + logging action
```
2024-01-15 10:30:15: Starting central logging to example.com:8080
2024-01-15 10:30:45: Sending network logs to example.com:8080/api/logs
2024-01-15 10:31:15: Sending command logs to example.com:8080/api/logs
```

## Network Security Implementation

### Firewall Rules (setup-firewall.sh)
**How it works**: Uses iptables to block all outbound traffic by default, then allows only allowlisted domains
**Implementation**:
```bash
# Block all outbound traffic
sudo iptables -P OUTPUT DROP

# Allow only allowlisted domains
while IFS= read -r line; do
    domain=$(echo "$line" | xargs)
    if [[ -n "$domain" ]]; then
        ip=$(resolve_domain "$domain")
        sudo iptables -A OUTPUT -d "$ip" -j ACCEPT
    fi
done < "$ALLOWLIST_FILE"

# Log all blocked connections
sudo iptables -A OUTPUT -j LOG --log-prefix "BLOCKED_OUTPUT: " --log-level 4
sudo iptables -A OUTPUT -j DROP
```

### Allowlist Configuration
**Purpose**: Defines which domains the agent can access
**Format**: One domain per line, comments with #
**Example**:
```
# Essential services
github.com
api.github.com
pypi.org
registry.npmjs.org

# Add your domains here
# your-api.com
# api.your-service.com
```

## Usage Instructions

### Deploy Agent
1. Use this configuration in Cursor background agent
2. Agent will automatically set up logging and monitoring
3. Check terminal tab for real-time command logs

### Monitor Logs
- **Terminal**: `tail -f /var/log/agent/commands.log`
- **Network**: `tail -f /var/log/agent/network.log`
- **System**: `tail -f /var/log/agent/system.log`

### External Logging
- Set `LOG_SERVER` environment variable (default: example.com:8080)
- Logs automatically sent to external server every 30 seconds
- JSON format with timestamp, type, message, hostname

## Monitoring Features

### Process Monitoring
**What it tracks**: All running processes, top processes by CPU/memory, process counts
**How often**: Every 30 seconds
**Tools used**: `ps aux`, `ps aux --sort=-%cpu`, `ps aux --sort=-%mem`

### Service Monitoring
**What it tracks**: Running systemd services, failed services, listening ports, Docker containers
**How often**: Every 30 seconds
**Tools used**: `systemctl list-units`, `netstat -tuln`, `docker ps`

### Network Monitoring
**What it tracks**: Active connections, network interface statistics, blocked connection attempts
**How often**: Every 5 seconds
**Tools used**: `ss -tuln`, `cat /proc/net/dev`, `dmesg`

### Command Auditing
**What it tracks**: Every terminal command with full context
**How often**: Real-time on every command
**Tools used**: bash PROMPT_COMMAND, DEBUG trap

## Configuration

### Environment Variables
- `LOG_SERVER` - External logging server (default: example.com:8080)
- `LOG_ENDPOINT` - Logging endpoint (default: /api/logs)

### Log Rotation
**Configuration**: Daily rotation, 7 days retention, automatic compression
**Implementation**: `/etc/logrotate.d/agent-logs`
```bash
/var/log/agent/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 666 agent agent
}
```

## Troubleshooting

### Check Logs
```bash
# View all logs
ls -la /var/log/agent/

# Check specific log
tail -f /var/log/agent/commands.log
```

### Network Issues
```bash
# Check firewall rules
sudo iptables -L

# Check blocked connections
dmesg | grep BLOCKED_OUTPUT
```

### Service Status
```bash
# Check monitoring processes
ps aux | grep monitor

# Check log files
ls -la /var/log/agent/
```

This system provides comprehensive logging and monitoring for Cursor background agents with network security and external log forwarding capabilities.