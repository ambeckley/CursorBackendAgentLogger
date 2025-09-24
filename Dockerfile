# Aaron Beckley 2025
# Use Ubuntu as base image
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LOG_DIR=/var/log/agent

# Install essential packages for shell-based monitoring
RUN apt-get update && apt-get install -y \
    iptables \
    netfilter-persistent \
    iptables-persistent \
    netstat \
    ss \
    lsof \
    curl \
    git \
    vim \
    nano \
    htop \
    sudo \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create logging directories
RUN mkdir -p $LOG_DIR

# Create a non-root user for the agent
RUN useradd -m -s /bin/bash agent && \
    usermod -aG sudo agent && \
    echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up logging permissions
RUN chown -R agent:agent $LOG_DIR

# Set the startup script as entrypoint
ENTRYPOINT ["/usr/local/bin/startup.sh"]
CMD ["bash"]