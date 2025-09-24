#!/bin/bash
# .cursor/setup-network.sh - Setup network restrictions
# Aaron Beckley 2025

echo "Setting up network restrictions..."

# Create allowlist file if it doesn't exist
sudo mkdir -p /etc/agent
if [ ! -f "/etc/agent/allowlist.txt" ]; then
    sudo tee /etc/agent/allowlist.txt > /dev/null << 'EOF'
# Essential services
github.com
api.github.com
raw.githubusercontent.com
pypi.org
files.pythonhosted.org
registry.npmjs.org
registry.yarnpkg.com
nodejs.org
python.org
ubuntu.com
archive.ubuntu.com
security.ubuntu.com
ppa.launchpad.net
EOF
fi

# Create firewall setup script
sudo tee /usr/local/bin/setup-firewall.sh > /dev/null << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/agent/network.log"
ALLOWLIST_FILE="/etc/agent/allowlist.txt"

resolve_domain() {
    local domain=$1
    nslookup "$domain" | grep -A1 "Name:" | tail -1 | awk '{print $2}' | head -1
}

log_network() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

log_network "Setting up network restrictions..."

sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F

sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT DROP

sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT

sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
        continue
    fi
    
    domain=$(echo "$line" | xargs)
    
    if [[ -n "$domain" ]]; then
        if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            sudo iptables -A OUTPUT -d "$domain" -j ACCEPT
            log_network "Allowed IP: $domain"
        else
            ip=$(resolve_domain "$domain")
            if [[ -n "$ip" ]]; then
                sudo iptables -A OUTPUT -d "$ip" -j ACCEPT
                log_network "Allowed domain: $domain -> $ip"
            else
                log_network "Failed to resolve domain: $domain"
            fi
        fi
    fi
done < "$ALLOWLIST_FILE"

sudo iptables -A OUTPUT -j LOG --log-prefix "BLOCKED_OUTPUT: " --log-level 4
sudo iptables -A OUTPUT -j DROP

sudo iptables-save > /etc/iptables/rules.v4

log_network "Network restrictions configured successfully"

/usr/local/bin/network-monitor.sh &
EOF

# Make firewall script executable
sudo chmod +x /usr/local/bin/setup-firewall.sh

echo "Network restrictions configured successfully!"
