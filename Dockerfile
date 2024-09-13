# Note: You can use any Debian/Ubuntu based image you want. 
FROM ubuntu:22.04
ARG USERNAME=cardano
ARG GID=1000
ARG UID=1000

ARG CARDANO_NODE_VERSION
ARG RPC_PORT

# Copy SSL certs (If present)
COPY .devcontainer/ssl-certs /ssl-certs

# Install common tools and setup ssl if present
RUN  apt update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y software-properties-common curl \
    # setup ssl certs
    && cp /ssl-certs/*.crt /usr/local/share/ca-certificates/ \
    && update-ca-certificates \
    # Upgrade
    && apt upgrade -y \
    # Clean up
    && apt purge --remove software-properties-common -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Setup cardano
RUN \
    # Cd to temp directory
    mkdir /tmp/cardano \
    && cd /tmp/cardano \
    # Download binary files and extract
    && curl -o cardano.tar.gz -L https://github.com/IntersectMBO/cardano-node/releases/download/${CARDANO_NODE_VERSION}/cardano-node-${CARDANO_NODE_VERSION}-linux.tar.gz \
    && tar xfvz cardano.tar.gz \
    && mv bin/* /usr/local/bin/ \
    && cd / \
    && rm -rf /tmp/cardano


# Setup non root user
RUN \
    # Add user $USERNAME
    groupadd --gid $GID $USERNAME \
    && useradd --uid $UID --gid $GID -m $USERNAME \
    # Change user shell to bash
    && usermod -s /bin/bash $USERNAME \
    # Make folder for db and ipc socker
    && mkdir -p /data /ipc \
    && chown $USERNAME:$USERNAME /data /ipc

# Use the user created
USER $USERNAME
ENTRYPOINT [ "/usr/local/bin/cardano-node" ]

#RPC port
EXPOSE ${RPC_PORT}

# Metrics port
EXPOSE 12798
