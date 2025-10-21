#!/usr/bin/env bash
# deploy.sh - Automated deployment script for Dockerized app to remote Linux host
# Requirements: bash, git, rsync, ssh client, curl/wget locally
# POSIX-friendly but uses bash arrays and features for convenience.
# Usage: ./deploy.sh
# Optional flags: --cleanup (remove deployed resources), --non-interactive (read env vars), --repo <url> ...

set -o errexit
set -o pipefail
set -o nounset

########################################
# Globals & Defaults
########################################
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOGFILE="deploy_${TIMESTAMP}.log"
EXITCODE=0
CLEANUP=false
NON_INTERACTIVE=false

# Defaults
BRANCH="main"
LOCAL_TMP_DIR="/tmp/deploy_${TIMESTAMP}"
RSYNC_EXCLUDES=(".git" ".env" "node_modules" "__pycache__")

########################################
# Utilities
########################################
log() {
  printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$LOGFILE"
}
die() {
  local code=${2:-1}
  log "ERROR: $1"
  exit "$code"
}
info() { log "INFO: $*"; }
warn() { log "WARN: $*"; }

trap 'last_err=$?; if [ "$last_err" -ne 0 ]; then log "Script failed with exit code $last_err"; fi' EXIT

########################################
# Arg parsing
########################################
while [ $# -gt 0 ]; do
  case "$1" in
    --cleanup) CLEANUP=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --pat) PAT="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --user) REMOTE_USER="$2"; shift 2 ;;
    --host) REMOTE_HOST="$2"; shift 2 ;;
    --key) SSH_KEY="$2"; shift 2 ;;
    --port) APP_PORT="$2"; shift 2 ;;
    *) warn "Unknown arg: $1"; shift ;;
  esac
done

########################################
# Prompt / read inputs (unless non-interactive)
########################################
prompt() {
  local varname="$1"; local prompt_text="$2"; local default="${3:-}"
  if [ "${NON_INTERACTIVE}" = true ] && [ -z "${!varname:-}" ]; then
    die "Missing required variable $varname in non-interactive mode"
  fi
  if [ -z "${!varname:-}" ]; then
    if [ -n "$default" ]; then
      read -r -p "$prompt_text [$default]: " tmp
      tmp="${tmp:-$default}"
    else
      read -r -p "$prompt_text: " tmp
    fi
    eval "$varname=\"\$tmp\""
  fi
}

# Collect parameters
prompt REPO_URL "Git repository URL (https or ssh)"
if [ -z "${PAT:-}" ]; then
  read -r -p "Use Personal Access Token for HTTPS clone? (y/N): " _use_pat
  if [ "${_use_pat:-N}" = "y" ] || [ "${_use_pat:-N}" = "Y" ]; then
    read -r -s -p "Enter Git Personal Access Token (PAT): " PAT
    echo
  fi
fi
prompt BRANCH "Branch name" "main"
prompt REMOTE_USER "Remote server SSH username" "ubuntu"
prompt REMOTE_HOST "Remote server IP or hostname"
prompt SSH_KEY "Path to private SSH key for remote (e.g. ~/.ssh/id_rsa)"
prompt APP_PORT "Application internal container port (e.g. 5000)" "5000"

########################################
# Basic validation
########################################
log "Starting deployment. Logfile: $LOGFILE"
mkdir -p "$LOCAL_TMP_DIR"
info "Working dir: $LOCAL_TMP_DIR"

# Validate SSH key
if [ ! -f "$SSH_KEY" ]; then
  die "SSH key not found at $SSH_KEY"
fi

# Validate REPO_URL
if ! printf '%s' "$REPO_URL" | grep -Eq '(^https?://|git@)'; then
  die "Invalid repo URL: $REPO_URL"
fi

########################################
# Helper: run ssh with key and capture output
########################################
ssh_exec() {
  local cmd="$1"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "$cmd"
}

ssh_exec_redirect() {
  local cmd="$1"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "$cmd" 2>&1 | tee -a "$LOGFILE"
}

########################################
# Cleanup mode (optional)
########################################
if [ "$CLEANUP" = true ]; then
  info "Running cleanup on remote host..."
  ssh_exec_redirect "sudo systemctl stop nginx || true; sudo docker ps -a --format '{{.Names}}' | xargs -r -n1 sudo docker rm -f || true; sudo docker network prune -f || true; sudo rm -f /etc/nginx/sites-enabled/*deploy_* /etc/nginx/sites-available/*deploy_* || true; sudo systemctl reload nginx || true; echo CLEANUP_DONE"
  info "Local cleanup..."
  rm -rf "$LOCAL_TMP_DIR"
  info "Cleanup complete."
  exit 0
fi

########################################
# Clone or update repo locally
########################################
cd "$LOCAL_TMP_DIR"
REPO_DIR=""
# Use PAT for HTTPS cloning if provided (note: embedding tokens in URL may store in shell history)
if printf '%s' "$REPO_URL" | grep -E '^https?://'; then
  if [ -n "${PAT:-}" ]; then
    # Insert PAT into URL: https://<PAT>@github.com/owner/repo.git
    safe_url="$(printf '%s' "$REPO_URL" | sed -E "s#https?://#https://${PAT}@#")"
  else
    safe_url="$REPO_URL"
  fi
  # extract repo dir
  repo_name="$(basename -s .git "$REPO_URL")"
  REPO_DIR="$LOCAL_TMP_DIR/$repo_name"
  if [ -d "$REPO_DIR/.git" ]; then
    info "Repo exists locally. Pulling latest on branch $BRANCH..."
    cd "$REPO_DIR"
    git fetch --all --prune 2>&1 | tee -a "$LOGFILE" || die "git fetch failed"
    git checkout "$BRANCH" 2>&1 | tee -a "$LOGFILE" || die "git checkout $BRANCH failed"
    git pull origin "$BRANCH" 2>&1 | tee -a "$LOGFILE" || die "git pull failed"
  else
    info "Cloning repo..."
    git clone --branch "$BRANCH" "$safe_url" || die "git clone failed"
    REPO_DIR="$LOCAL_TMP_DIR/$repo_name"
  fi
else
  # SSH clone
  repo_name="$(basename -s .git "$REPO_URL")"
  REPO_DIR="$LOCAL_TMP_DIR/$repo_name"
  if [ -d "$REPO_DIR/.git" ]; then
    info "Repo exists locally. Pulling latest..."
    cd "$REPO_DIR"
    git fetch --all --prune 2>&1 | tee -a "$LOGFILE"
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
  else
    git clone --branch "$BRANCH" "$REPO_URL" || die "git clone failed"
    REPO_DIR="$LOCAL_TMP_DIR/$repo_name"
  fi
fi

# Navigate into repo
cd "$REPO_DIR" || die "Failed to enter repo dir"

info "Repository at $REPO_DIR"

# Verify Dockerfile or docker-compose
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
  COMPOSE_PRESENT=true
  info "Found docker-compose.yml"
elif [ -f "Dockerfile" ]; then
  COMPOSE_PRESENT=false
  info "Found Dockerfile"
else
  die "Neither Dockerfile nor docker-compose.yml found in project root"
fi

########################################
# Remote connectivity checks
########################################
info "Testing SSH connectivity to ${REMOTE_USER}@${REMOTE_HOST}..."
if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "${REMOTE_USER}@${REMOTE_HOST}" 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then
  info "SSH connectivity OK"
else
  die "SSH connectivity failed. Check username, host, and key."
fi

info "Checking remote sudo availability..."
if ssh -i "$SSH_KEY" -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" 'sudo -n true' 2>/dev/null; then
  info "User can run sudo without prompt (or sudo -n succeeded)."
else
  warn "Remote sudo may prompt for password. Script will attempt operations with sudo; interactive password prompts might appear."
fi

########################################
# Prepare remote environment (install docker, docker-compose, nginx)
########################################
info "Preparing remote environment (update, install Docker, docker-compose, nginx if missing)..."

REMOTE_PREP_CMDS=$(cat <<'EOF'
set -e
# Determine package manager
if command -v apt-get >/dev/null 2>&1; then
  pkg=apt
elif command -v yum >/dev/null 2>&1; then
  pkg=yum
else
  echo "Unsupported package manager"
  exit 2
fi

# Update
if [ "$pkg" = "apt" ]; then
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https
  # Docker repo setup
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || true
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io || true
  fi
  # Docker Compose plugin (plugin approach)
  if ! docker compose version >/dev/null 2>&1; then
    sudo apt-get install -y docker-compose-plugin || true
  fi
  # Nginx
  if ! command -v nginx >/dev/null 2>&1; then
    sudo apt-get install -y nginx || true
  fi
elif [ "$pkg" = "yum" ]; then
  sudo yum install -y yum-utils
  if ! command -v docker >/dev/null 2>&1; then
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true
    sudo yum install -y docker-ce docker-ce-cli containerd.io || true
  fi
  if ! docker compose version >/dev/null 2>&1; then
    sudo yum install -y docker-compose-plugin || true
  fi
  if ! command -v nginx >/dev/null 2>&1; then
    sudo yum install -y epel-release && sudo yum install -y nginx || true
  fi
fi

# Start docker and nginx
sudo systemctl enable --now docker || true
sudo usermod -aG docker "$USER" || true
sudo systemctl enable --now nginx || true

# Output versions
echo "docker_version: $(docker --version || true)"
echo "docker_compose_version: $(docker compose version || true)"
echo "nginx_version: $(nginx -v 2>&1 || true)"

EOF
)

ssh_exec_redirect "$REMOTE_PREP_CMDS" || die "Remote environment preparation failed"

########################################
# Transfer project files (rsync)
########################################
info "Transferring project files to remote host..."
REMOTE_APP_DIR="/home/${REMOTE_USER}/deploy_${TIMESTAMP}"
# create remote dir
ssh_exec "mkdir -p ${REMOTE_APP_DIR} && sudo chown ${REMOTE_USER}:${REMOTE_USER} ${REMOTE_APP_DIR}"

# build rsync exclude args
RSYNC_EX_ARG=()
for ex in "${RSYNC_EXCLUDES[@]}"; do RSYNC_EX_ARG+=("--exclude=$ex"); done

rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" "${RSYNC_EX_ARG[@]}" "$REPO_DIR/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_APP_DIR}/" 2>&1 | tee -a "$LOGFILE" || die "rsync failed"

info "Files copied to ${REMOTE_HOST}:${REMOTE_APP_DIR}"

########################################
# Remote deploy (build/run)
########################################
REMOTE_SERVICE_NAME="deploy_${TIMESTAMP}"
REMOTE_DEPLOY_CMDS="set -e
cd ${REMOTE_APP_DIR}
# Optional: stop old containers with same name prefix
sudo docker ps -a --format '{{.Names}}' | grep -E '^${REMOTE_SERVICE_NAME}' && sudo docker ps -a --format '{{.Names}}' | grep -E '^${REMOTE_SERVICE_NAME}' | xargs -r sudo docker rm -f || true

# If docker-compose exists: use it
if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
  # Create docker compose project name to avoid conflicts
  sudo docker compose -p ${REMOTE_SERVICE_NAME} down || true
  sudo docker compose -p ${REMOTE_SERVICE_NAME} up -d --build
else
  # Build and run single container named after service
  if [ -f Dockerfile ]; then
    # Build image
    sudo docker build -t ${REMOTE_SERVICE_NAME}:latest .
    # Stop and remove old container
    sudo docker rm -f ${REMOTE_SERVICE_NAME} || true
    # Run container (map container port to ephemeral port and let nginx proxy to container)
    sudo docker run -d --name ${REMOTE_SERVICE_NAME} -p 0:${APP_PORT} --restart unless-stopped ${REMOTE_SERVICE_NAME}:latest
  else
    echo 'No Dockerfile or docker-compose found on remote; aborting'
    exit 2
  fi
fi

# small sleep for containers to initialize
sleep 5

# show running containers
sudo docker ps --filter name=${REMOTE_SERVICE_NAME} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Determine container internal port bindings for nginx (we assume app listens on container internal port: ${APP_PORT})
# Find host port mapping for container
HOST_PORT=$(sudo docker ps --filter name=${REMOTE_SERVICE_NAME} --format '{{.Ports}}' | sed -n 's/.*0.0.0.0:\([0-9]\+\)->.*/\1/p' | head -n1 | tr -d '\r' || true)
echo "HOST_PORT=${HOST_PORT:-none}"
if [ -z \"${HOST_PORT}\" ] || [ \"${HOST_PORT}\" = \"none\" ]; then
  echo 'Cannot determine host port mapping. If using docker compose, ensure ports are mapped in compose file.'
fi

# simple health-check: try curl inside host
if command -v curl >/dev/null 2>&1; then
  if [ -n \"${HOST_PORT}\" ] && [ \"${HOST_PORT}\" != \"none\" ]; then
    curl -sS --max-time 5 http://127.0.0.1:${HOST_PORT} || echo 'Local curl failed; service may still be starting'
  fi
fi

echo DEPLOY_DONE
"

# Export APP_PORT to remote shell by embedding into ssh command
ssh_exec_redirect "APP_PORT=${APP_PORT} ; ${REMOTE_DEPLOY_CMDS}" || die "Remote deploy commands failed"

########################################
# Configure Nginx on remote
########################################
info "Configuring Nginx reverse proxy on remote..."

# Build nginx config (proxy to 127.0.0.1:HOST_PORT or to container host port if known)
NGINX_CONF_REMOTE="/etc/nginx/sites-available/deploy_${TIMESTAMP}.conf"
NGINX_CONF_CONTENT="server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
"

# Create a temporary file locally then push it
tmp_conf="$(mktemp)"
printf '%s\n' "$NGINX_CONF_CONTENT" > "$tmp_conf"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$tmp_conf" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/deploy_nginx.conf" 2>&1 | tee -a "$LOGFILE"
rm -f "$tmp_conf"

# Move into place and enable
ssh_exec_redirect "sudo mv /tmp/deploy_nginx.conf ${NGINX_CONF_REMOTE} && sudo ln -sf ${NGINX_CONF_REMOTE} /etc/nginx/sites-enabled/deploy_${TIMESTAMP}.conf && sudo nginx -t && sudo systemctl reload nginx" || die "Nginx configuration or reload failed"

info "Nginx configured to proxy to app internal port ${APP_PORT}."

########################################
# Validation Checks
########################################
info "Validating deployment..."

# Check docker
ssh_exec_redirect "sudo systemctl is-active --quiet docker && echo 'docker_running' || echo 'docker_not_running'"

# Check container is running
ssh_exec_redirect "sudo docker ps --filter name=${REMOTE_SERVICE_NAME} --format 'table {{.Names}}\t{{.Status}}' || true"

# Test endpoint remotely via curl (from remote host to localhost)
ssh_exec_redirect "if command -v curl >/dev/null 2>&1; then curl -sS -o /dev/null -w 'HTTPREMOTE: %{http_code}\\n' http://127.0.0.1:${APP_PORT} || echo 'remote curl failed'; else echo 'no curl on remote'; fi"

# Test endpoint from local machine (to remote host via nginx on port 80)
if command -v curl >/dev/null 2>&1; then
  log "Testing via nginx from local: curl -I http://${REMOTE_HOST}"
  if curl -sS -I --max-time 10 "http://${REMOTE_HOST}" | tee -a "$LOGFILE"; then
    info "Local HTTP test to remote succeeded (see log)"
  else
    warn "Local HTTP test to remote failed; remote may block port 80 or firewall exists."
  fi
else
  warn "No curl locally to test HTTP endpoint"
fi

########################################
# Final notes and exit
########################################
info "Deployment finished. Logfile: $LOGFILE"
info "Remote app directory: ${REMOTE_APP_DIR}"
info "Nginx config: ${NGINX_CONF_REMOTE}"
info "If the app did not start, inspect remote logs: ssh -i ${SSH_KEY} ${REMOTE_USER}@${REMOTE_HOST} 'sudo docker logs <container_name>' or 'sudo docker compose -p ${REMOTE_SERVICE_NAME} logs'"

exit 0
