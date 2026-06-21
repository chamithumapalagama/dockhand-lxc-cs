#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/diyhue/diyHue

set -Eeuo pipefail

YW="\033[33m"
GN="\033[1;92m"
RD="\033[01;31m"
CL="\033[m"
BLD="\033[1m"
TAB="  "

msg_info()  { echo -e "${TAB}\033[1;34mℹ\033[m  ${1}..."; }
msg_ok()    { echo -e "${TAB}\033[1;92m✔\033[m  ${1}"; }
msg_warn()  { echo -e "${TAB}\033[33m⚠\033[m  ${1}"; }
msg_error() { echo -e "${TAB}\033[01;31m✖\033[m  ${1}"; exit 1; }

header_info() {
  clear
  cat <<'EOF'

  __  __           ____
 / / / / __  __  __/ / /_  __  _____
/ /_/ / / / / / / / / __ \/ / / / _ \
\__,_/_/_/_/_/_/_/_/_/ /_/\__,_/\___/
        diyHue Bridge Emulator

EOF
}

APP="diyHue"
PORT=80
HN="diyhue"
DISK=8
CORES=2
RAM=1024
BRG="vmbr0"
BRANCH_CHOICE="1"   # 1 = Master, 2 = Dev (matches install.sh prompt)

header_info

TEMPLATE_STORAGE=$(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1{print $1}' | head -n1)
CONTAINER_STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1{print $1}' | head -n1)

[[ -z "$TEMPLATE_STORAGE" ]]  && msg_error "No template storage found."
[[ -z "$CONTAINER_STORAGE" ]] && msg_error "No container storage found."

CTID=$(pvesh get /cluster/nextid 2>/dev/null)

echo -e "${BLD}⚙️  Default Settings:${CL}"
echo -e "${TAB}Container ID:  ${GN}${CTID}${CL}"
echo -e "${TAB}Hostname:      ${GN}${HN}${CL}"
echo -e "${TAB}OS:            ${GN}Debian 12${CL}"
echo -e "${TAB}Disk:          ${GN}${DISK}GB (${CONTAINER_STORAGE})${CL}"
echo -e "${TAB}CPU Cores:     ${GN}${CORES}${CL}"
echo -e "${TAB}RAM:           ${GN}${RAM}MiB${CL}"
echo -e "${TAB}Bridge:        ${GN}${BRG}${CL}"
echo -e "${TAB}Port:          ${GN}${PORT}${CL}"
echo -e "${TAB}Branch:        ${GN}$([ "$BRANCH_CHOICE" = "1" ] && echo Master || echo Dev)${CL}"
echo ""
read -rp "${TAB}Proceed with defaults? (y/N): " confirm
[[ ! "${confirm,,}" =~ ^(y|yes)$ ]] && { msg_warn "Aborted."; exit 0; }

msg_info "Updating template list"
pveam update >/dev/null 2>&1
TEMPLATE=$(pveam available --section system 2>/dev/null | awk '/debian-12-standard/{print $2}' | sort -V | tail -n1)
[[ -z "$TEMPLATE" ]] && msg_error "Could not find Debian 12 template."

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
  msg_info "Downloading ${TEMPLATE}"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null 2>&1
fi
msg_ok "Template ready: ${TEMPLATE}"

msg_info "Creating LXC container ${CTID}"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$HN" \
  --cores "$CORES" \
  --memory "$RAM" \
  --rootfs "${CONTAINER_STORAGE}:${DISK}" \
  --net0 "name=eth0,bridge=${BRG},ip=dhcp" \
  --unprivileged 1 \
  --features "nesting=1,keyctl=1" \
  --onboot 1 \
  --start 0 >/dev/null 2>&1
msg_ok "Created LXC container ${CTID}"

msg_info "Starting container"
pct start "$CTID"

msg_info "Waiting for IP allocation"
IP=""
while [ -z "$IP" ]; do
  sleep 2
  IP=$(pct exec "$CTID" -- ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 || true)
done
msg_ok "Container started"

msg_info "Installing dependencies"
pct exec "$CTID" -- bash -c "
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq curl unzip nmap netcat-openbsd >/dev/null 2>&1
"
msg_ok "Installed dependencies"

msg_info "Fetching official diyHue install.sh"
pct exec "$CTID" -- bash -c "
  curl -sL https://raw.githubusercontent.com/diyhue/diyHue/master/BridgeEmulator/install.sh -o /root/install.sh
  chmod +x /root/install.sh
"
msg_ok "Fetched install.sh"

msg_info "Installing ${APP} (this can take a few minutes)"
# install.sh prompts:
#   1) Branch selection (1=Master, 2=Dev) -> auto-answered via echo
#   2) Interface selection -> only triggers if >1 non-loopback interface exists;
#      a fresh LXC has only eth0, so this is skipped automatically.
pct exec "$CTID" -- bash -c "cd /root && echo '${BRANCH_CHOICE}' | bash install.sh"
msg_ok "Installed ${APP}"

echo ""
msg_ok "Completed successfully!"
echo ""
echo -e "${TAB}${GN}${BLD}${APP} is ready!${CL}"
echo -e "${TAB}Access: ${GN}http://${IP}${CL}"
echo -e "${TAB}Service: ${GN}pct exec ${CTID} -- systemctl status hue-emulator.service${CL}"
echo ""
