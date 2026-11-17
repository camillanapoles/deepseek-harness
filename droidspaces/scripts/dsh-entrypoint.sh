#!/bin/sh
# Services the DeepSeek Harness image publishes when the container starts.
#
#   - the DeepSeek Harness Web UI on DSH_WEB_PORT
#   - the repository over git on DSH_GIT_PORT
#   - the repository over HTTP on DSH_REPO_HTTP_PORT
#
# Every service runs under a supervisor loop: a service that exits is logged
# and started again, because a phone suspends and resumes its containers.

set -eu

DSH_REPO_DIR=${DSH_REPO_DIR:-/opt/deepseek-harness}
DSH_HOME=${DSH_HOME:-/var/lib/dsh}
DSH_WEB_PORT=${DSH_WEB_PORT:-3080}
DSH_GIT_PORT=${DSH_GIT_PORT:-9418}
DSH_REPO_HTTP_PORT=${DSH_REPO_HTTP_PORT:-8080}
export DSH_HOME

log() {
  printf '[droidspaces] %s\n' "$*"
}

supervise() {
  name=$1
  shift
  while :; do
    log "starting $name"
    "$@" || log "$name exited; starting it again"
    sleep 3
  done
}

# The Web UI binds one concrete address; the runtime rejects a wildcard bind.
container_ip() {
  ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1
}

ip_address=$(container_ip)
if [ -z "$ip_address" ]; then
  ip_address=127.0.0.1
  log 'no global address yet; serving on loopback until the runtime assigns one'
fi

if [ -f "$DSH_REPO_DIR/.dsh-commit" ]; then
  log "repository commit $(cat "$DSH_REPO_DIR/.dsh-commit")"
fi
log "repository directory $DSH_REPO_DIR"

supervise 'harness web ui' dsh web --host "$ip_address" --port "$DSH_WEB_PORT" --no-open &
supervise 'repository git daemon' \
  git daemon --reuseaddr --informative-errors --export-all \
  --base-path=/opt --port="$DSH_GIT_PORT" /opt &
supervise 'repository http server' \
  node /usr/local/lib/dsh/serve-repo.mjs --root "$DSH_REPO_DIR" --port "$DSH_REPO_HTTP_PORT" &

log "web ui http://$ip_address:$DSH_WEB_PORT/ (the launch token is printed by the harness)"
log "repository git://$ip_address:$DSH_GIT_PORT/deepseek-harness"
log "repository http://$ip_address:$DSH_REPO_HTTP_PORT/"

wait || true
