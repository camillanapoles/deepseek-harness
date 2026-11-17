#!/bin/sh
# Container init for the DeepSeek Harness Droidspaces image.
#
# Droidspaces executes /sbin/init as PID 1 inside the container. This script
# owns the parts the image is responsible for: the kernel filesystems the
# runtime does not already provide, the address the runtime hands out, and the
# services published afterwards. It stays in the foreground so the container
# keeps running until Droidspaces stops it.

set -eu

DSH_REPO_DIR=${DSH_REPO_DIR:-/opt/deepseek-harness}
DSH_HOME=${DSH_HOME:-/var/lib/dsh}
export DSH_HOME

log() {
  printf '[droidspaces-init] %s\n' "$*"
}

# The runtime mounts /proc, /sys and /dev itself. Mounting them again fails
# with "busy", which this script treats as "already there".
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true

mkdir -p "$DSH_HOME"
chmod 700 "$DSH_HOME"

# NAT mode hands the container its address from the runtime's own DHCP
# server, so the image asks for a lease when the interface carries none.
if ip link show eth0 >/dev/null 2>&1; then
  ip link set eth0 up 2>/dev/null || true
  if ip -4 -o addr show dev eth0 2>/dev/null | grep -q .; then
    log 'eth0 already carries an address'
  else
    log 'requesting an address over DHCP'
    udhcpc -i eth0 -n -q -t 5 -T 2 -s /usr/local/lib/dsh/udhcpc.script \
      || log 'the DHCP request failed; continuing with the addresses the runtime provided'
  fi
else
  log 'no eth0 interface; skipping the address request'
fi

exec /usr/local/lib/dsh/dsh-entrypoint.sh
