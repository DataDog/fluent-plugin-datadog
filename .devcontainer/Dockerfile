# Use a Ruby image >= 3.1, as required by some dependencies like recent nokogiri
FROM ruby:3.2-slim-bookworm

# Prevent interactive prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies required for building gems with native extensions
# and for general development.
# - build-essential: For compiling native extensions
# - git: For cloning repos if needed, although VS Code handles the main clone
# - curl, wget: Useful general tools
# - libxml2-dev, libxslt1-dev: Needed by nokogiri gem
# - zlib1g-dev: Needed by many gems
# - sqlite3, libsqlite3-dev: Needed by some gems that might be transitively included
# - libssl-dev: Needed for secure connections, potentially by some gems
# - pkg-config: Build helper
# - make: Used by the Makefile in the repo
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    wget \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    sqlite3 \
    libsqlite3-dev \
    libssl-dev \
    pkg-config \
    make \
    zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# (Optional but Recommended) Create a non-root user for development
# This matches the default user setup by Dev Containers 'automatic' creation
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    # Add the new user to the sudo group to allow them to run commands with sudo
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(ALL\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

# Set Zsh as the default shell for the non-root user
# Needs to be run as root, after the user is created and zsh is installed
RUN chsh -s $(which zsh) ${USERNAME}

# Set the default working directory for subsequent commands and where the project code will be mounted
WORKDIR /workspaces

# Switch to the non-root user
USER $USERNAME

# The project code will be mounted into /workspaces by Dev Containers.
# Dependencies will be installed via postCreateCommand in devcontainer.json
