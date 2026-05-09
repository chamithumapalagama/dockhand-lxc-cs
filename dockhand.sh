#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://dockhand.pro/ | Github: https://github.com/Finsys/dockhand

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)

set -Eeuo pipefail
trap 'error_handler' ERR

APP="Dockhand"
PORT=3000

header_info "$APP"

# ==============================================================================
# DEFAULTS
# ==============================================================================
CTID=$(pvesh get /cluster/nextid)
HN="dockhand"
DISK=8
CORES=2
RAM=2048
BRG="vmbr0"

TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR>1{print $1}' | head -n1)
CONTAINER_STORAGE=$(pvesm status -content rootdir | awk 'NR>1{print $1}' | head -n1)

echo ""
echo -e "⚙️  Default Settings:"
echo -e "${TAB}Container ID:    ${CTID}"
echo -e "${TAB}Hostname:        ${HN}"
echo -e "${TAB}OS:              Debian 12"
echo -e "${TAB}Disk:            ${DISK}GB  (${CONTAINER_STORAGE})"
echo -e "${TAB}CPU Cores:       ${CORES}"
echo -e "${TAB}RAM:             ${RAM}MiB"
echo -e "${TAB}Network:         DHCP on ${BRG}"
echo -e "${TAB}Port:            ${PORT}"
echo ""
echo -n "${TAB}Proceed with defaults? (y/N): "
read -r confirm
[[ ! "${confirm,,}" =~ ^(y|yes)$ ]] && { msg_warn "Aborted."; exit 0; }

# ==============================================================================
# TEMPLATE
# ==============================================================================
msg_info "Updating template list"
pveam update >/dev/null 2>&1
TEMPLATE=$(pveam available --section system | awk '/debian-12-standard/{print $2}' | sort -V | tail -n1)
if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
  msg_info "Downloading Debian 12 template"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null 2>&1
fi
msg_ok "Template ready: ${TEMPLATE}"

# ==============================================================================
# CREATE LXC
# ==============================================================================
msg_info "Creating LXC container (${CTID})"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$HN" \
  --cores "$CORES" \
  --memory "$RAM" \
  --rootfs "${CONTAINER_STORAGE}:${DISK}" \
  --net0 "name=eth0,bridge=${BRG},ip=dhcp" \
  --unprivileged 1 \
  --features "nesting=1" \
  --onboot 1 \
  --start 0 >/dev/null 2>&1
msg_ok "Created LXC container (${CTID})"

msg_info "Starting container"
pct start "$CTID"
sleep 8
msg_ok "Container started"

IP=$(pct exec "$CTID" -- ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)

# ==============================================================================
# INSTALL DOCKER
# ==============================================================================
msg_info "Installing Docker"
pct exec "$CTID" -- bash -c "
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq curl ca-certificates >/dev/null 2>&1
  mkdir -p /etc/docker
  printf '{\"log-driver\":\"journald\"}\n' > /etc/docker/daemon.json
  sh <(curl -fsSL https://get.docker.com) >/dev/null 2>&1
"
msg_ok "Installed Docker"

# ==============================================================================
# INSTALL DOCKHAND
# ==============================================================================
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

# ==============================================================================
# DONE
# ==============================================================================
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${PORT}${CL}"