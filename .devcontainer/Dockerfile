# Note: You can use any Debian/Ubuntu based image you want. 
FROM ubuntu:22.04
ARG USERNAME=vscode
ARG ALLOWROOT=yes
ARG GID=1000
ARG UID=1000
ARG WORKSPACE_FOLDER

# Copy SSL certs (If present)
COPY ssl-certs /ssl-certs

# Install common tools, latest git, setup ssl certs and upgrade
RUN  apt update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y software-properties-common nano curl lsb-release openssh-client \
    # setup ssl certs
    && cp /ssl-certs/*.crt /usr/local/share/ca-certificates/ \
    && update-ca-certificates \
    # Install git
    && add-apt-repository ppa:git-core/ppa -y \
    && apt install -y git \
    # Upgrade
    && apt upgrade -y \
    # Clean up
    && apt purge --remove -y software-properties-common \
    && apt autoremove -y

# Setup non root user
RUN \
    # Add user $USERNAME
    groupadd --gid $GID $USERNAME \
    && useradd --uid $UID --gid $GID -m $USERNAME \
    # Setup sudo for root access and add user to sudoers if allowroot = yes
    && if [ "$ALLOWROOT" = "yes" ]; then \
        apt update; \
        apt install -y sudo; \
        echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME; \
        chmod 0440 /etc/sudoers.d/$USERNAME; \
    fi \
    # Change user shell to bash
    && usermod -s /bin/bash $USERNAME \
    # create workspace directory
    && mkdir -p $WORKSPACE_FOLDER \
    && chown $USERNAME:$USERNAME $WORKSPACE_FOLDER

# Use the user created
USER $USERNAME
