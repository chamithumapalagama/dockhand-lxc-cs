#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://dockhand.pro/ | Github: https://github.com/Finsys/dockhand

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Dockhand"
var_tags="docker;management"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"

base_settings() {
  CT_ID=$NEXTID
  CT_TYPE="1"
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

base_settings
variables
color
catch_errors

function update_script() {
  header_info
  if [[ ! -f /opt/dockhand/docker-compose.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  cd /opt/dockhand
  docker compose pull
  docker compose up -d --remove-orphans
  msg_ok "Updated ${APP}"
  exit
}

start
build_container

# ==============================================================================
# INSTALL INSIDE THE LXC
# ==============================================================================
msg_info "Installing Docker"
pct exec "$CTID" -- bash -c "
  mkdir -p /etc/docker
  printf '{\"log-driver\":\"journald\"}\n' > /etc/docker/daemon.json
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates
  sh <(curl -fsSL https://get.docker.com) > /dev/null 2>&1
"
msg_ok "Installed Docker"

msg_info "Installing ${APP}"
pct exec "$CTID" -- bash -c "
  mkdir -p /opt/dockhand/data
  cat > /opt/dockhand/docker-compose.yaml << 'EOF'
services:
  dockhand:
    image: fnsys/dockhand:latest
    container_name: dockhand
    restart: unless-stopped
    ports:
      - 3000:3000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/dockhand/data:/app/data
EOF
  cd /opt/dockhand
  docker compose up -d
"
msg_ok "Installed ${APP}"

description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL."
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"