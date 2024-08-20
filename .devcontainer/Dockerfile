# Note: You can use any Debian/Ubuntu based image you want. 
FROM ubuntu:22.04
ARG USERNAME=vscode
ARG ALLOWROOT=yes
ARG GID=1000
ARG UID=1000

# Copy fix permission script
COPY fix-ownership.sh /usr/local/share/fix-ownership.sh

# Setup non root user
RUN \
    # Add user $USERNAME
    groupadd --gid $GID $USERNAME \
    && useradd --uid $UID --gid $GID -m $USERNAME \
    # Install some tools
    && apt update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt install -y nano curl lsb-release openssh-client \
    # Setup sudo for root access Add user to sudoers if allowroot = yes
    && if [ "$ALLOWROOT" = "yes" ]; then \
        apt install -y sudo; \
        echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME; \
        chmod 0440 /etc/sudoers.d/$USERNAME; \
    fi \
    # Change user shell to bash
    && usermod -s /bin/bash $USERNAME \
    # Cleanup
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    # Fix ownership script
    && sed -i "s/USERNAME/$USERNAME/g" /usr/local/share/fix-ownership.sh

# Use the user created
USER $USERNAME
