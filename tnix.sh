#!/usr/bin/env bash

# ==========================================================
# ████████╗███╗   ██╗██╗██╗  ██╗
# ╚══██╔══╝████╗  ██║██║╚██╗██╔╝
#    ██║   ██╔██╗ ██║██║ ╚███╔╝
#    ██║   ██║╚██╗██║██║ ██╔██╗
#    ██║   ██║ ╚████║██║██╔╝ ██╗
#    ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
#
#                    T N I X  V2
#        Docker / Bare Metal + Nginx + SSL
# ==========================================================
#
# TNIX v2 supports two deployment modes:
#   1) Docker     - Docker image + Compose + systemd + Nginx
#   2) Bare Metal - Original Flask + Gunicorn + systemd + Nginx
#
# Docker is recommended for new/commercial deployments.
# Bare Metal preserves the original TNIX deployment workflow.
# ==========================================================

set -Eeuo pipefail

trap 'echo "❌ TNIX failed at line $LINENO. Command: $BASH_COMMAND" >&2' ERR

clear

echo ""
echo "████████╗███╗   ██╗██╗██╗  ██╗"
echo "╚══██╔══╝████╗  ██║██║╚██╗██╔╝"
echo "   ██║   ██╔██╗ ██║██║ ╚███╔╝ "
echo "   ██║   ██║╚██╗██║██║ ██╔██╗ "
echo "   ██║   ██║ ╚████║██║██╔╝ ██╗"
echo "   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝"
echo ""
echo "🚀 Flask VPS Deployment Wizard"
echo "🐳 Docker or 🐍 Bare Metal"
echo "🌍 Nginx + HTTPS"
echo ""

echo "=================================================="
echo "🚀 SELECT DEPLOYMENT TYPE"
echo "=================================================="
echo ""
echo "1) Docker"
echo "   Docker image + Docker Compose + systemd"
echo ""
echo "2) Bare Metal"
echo "   Original Flask + Gunicorn + Python venv + systemd"
echo ""

while true; do
    read -r -p "Select deployment type [1-2]: " DEPLOYMENT_TYPE
    case "$DEPLOYMENT_TYPE" in
        1)
            echo ""
            echo "🐳 Docker deployment selected."
            echo ""
            break
            ;;
        2)
            echo ""
            echo "🐍 Bare Metal deployment selected."
            echo ""
            break
            ;;
        *)
            echo "❌ Invalid selection. Please choose 1 or 2."
            ;;
    esac
done

run_docker() {
    # ----------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------

    log() {
        echo ""
        echo "=================================================="
        echo "$1"
        echo "=================================================="
    }

    info() {
        echo "➡️  $1"
    }

    success() {
        echo "✅ $1"
    }

    warn() {
        echo "⚠️  $1"
    }

    fail() {
        echo "❌ $1" >&2
        exit 1
    }

    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }

    ask_yes_no() {
        local prompt="$1"
        local default="${2:-y}"
        local answer

        while true; do
            if [[ "$default" == "y" ]]; then
                read -r -p "$prompt (Y/n): " answer
                answer="${answer:-y}"
            else
                read -r -p "$prompt (y/N): " answer
                answer="${answer:-n}"
            fi

            case "${answer,,}" in
                y|yes) return 0 ;;
                n|no) return 1 ;;
                *) echo "Please answer y or n." ;;
            esac
        done
    }

    require_root() {
        if [[ "$(id -u)" -ne 0 ]]; then
            fail "Run TNIX as root (sudo ./tnix-v2-docker.sh)."
        fi
    }

    # ----------------------------------------------------------
    # Banner
    # ----------------------------------------------------------

    clear || true

    echo ""
    echo "████████╗███╗   ██╗██╗██╗  ██╗"
    echo "╚══██╔══╝████╗  ██║██║╚██╗██╔╝"
    echo "   ██║   ██╔██╗ ██║██║ ╚███╔╝ "
    echo "   ██║   ██║╚██╗██║██║ ██╔██╗ "
    echo "   ██║   ██║ ╚████║██║██╔╝ ██╗"
    echo "   ╚═╝   ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝"
    echo ""
    echo "🐳 TNIX v2 — Docker VPS Deployment Wizard"
    echo "🌍 Docker Compose + systemd + Nginx + HTTPS"
    echo ""

    require_root

    # ----------------------------------------------------------
    # User inputs
    # ----------------------------------------------------------

    log "📋 APPLICATION CONFIGURATION"

    read -r -p "Enter domain name (example.com): " DOMAIN
    [[ -n "$DOMAIN" ]] || fail "Domain is required."

    read -r -p "Enter project root path: " PROJECT_DIR
    [[ -n "$PROJECT_DIR" ]] || fail "Project directory is required."
    PROJECT_DIR="${PROJECT_DIR%/}"
    [[ -d "$PROJECT_DIR" ]] || fail "Project directory does not exist: $PROJECT_DIR"

    read -r -p "Enter Flask app module (example: app:app): " APP_MODULE
    [[ -n "$APP_MODULE" ]] || fail "Flask app module is required."

    read -r -p "Enter service name [default: tnixapp]: " SERVICE_NAME
    SERVICE_NAME="${SERVICE_NAME:-tnixapp}"
    SERVICE_NAME="$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_.-' '-')"

    read -r -p "Enter container/app port [default: 8000]: " APP_PORT
    APP_PORT="${APP_PORT:-8000}"
    [[ "$APP_PORT" =~ ^[0-9]+$ ]] || fail "APP_PORT must be numeric."
    (( APP_PORT >= 1024 && APP_PORT <= 65535 )) || fail "APP_PORT must be between 1024 and 65535."

    read -r -p "Enter image name [default: $SERVICE_NAME]: " IMAGE_NAME
    IMAGE_NAME="${IMAGE_NAME:-$SERVICE_NAME}"

    read -r -p "Enter image tag [default: latest]: " IMAGE_TAG
    IMAGE_TAG="${IMAGE_TAG:-latest}"

    if ask_yes_no "Build Docker image locally from this project?" "y"; then
        BUILD_LOCAL="true"
    else
        BUILD_LOCAL="false"
    fi

    read -r -p "Enter health-check path [default: /health]: " HEALTH_PATH
    HEALTH_PATH="${HEALTH_PATH:-/health}"

    read -r -p "Enter SSL email: " SSL_EMAIL
    [[ -n "$SSL_EMAIL" ]] || fail "SSL email is required."

    read -r -p "Include www.$DOMAIN in SSL certificate? (y/n) [default: n]: " INCLUDE_WWW
    INCLUDE_WWW="${INCLUDE_WWW:-n}"

    # ----------------------------------------------------------
    # Derived paths
    # ----------------------------------------------------------

    DEPLOY_DIR="$PROJECT_DIR"
    COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"
    DOCKERFILE="$PROJECT_DIR/Dockerfile"
    DOCKERIGNORE="$PROJECT_DIR/.dockerignore"
    ENV_FILE="$DEPLOY_DIR/.env"
    NGINX_CONF="/etc/nginx/sites-available/${SERVICE_NAME}"
    NGINX_LINK="/etc/nginx/sites-enabled/${SERVICE_NAME}"
    SYSTEMD_SERVICE="/etc/systemd/system/${SERVICE_NAME}.service"
    CONTAINER_NAME="$SERVICE_NAME"
    COMPOSE_PROJECT="$SERVICE_NAME"

    if [[ "$INCLUDE_WWW" =~ ^[Yy]$ ]]; then
        CERTBOT_DOMAINS=("-d" "$DOMAIN" "-d" "www.$DOMAIN")
        NGINX_SERVER_NAMES="$DOMAIN www.$DOMAIN"
    else
        CERTBOT_DOMAINS=("-d" "$DOMAIN")
        NGINX_SERVER_NAMES="$DOMAIN"
    fi

    # ----------------------------------------------------------
    # Project validation
    # ----------------------------------------------------------

    log "🔎 VALIDATING PROJECT"

    [[ -f "$PROJECT_DIR/requirements.txt" ]] || fail "requirements.txt not found in $PROJECT_DIR"

    if [[ "$BUILD_LOCAL" == "true" ]]; then
        if [[ ! -f "$DOCKERFILE" ]]; then
            warn "Dockerfile not found. TNIX will generate one."
        else
            info "Existing Dockerfile detected. TNIX will use it."
        fi
    fi

    if [[ "$HEALTH_PATH" != "none" && "$HEALTH_PATH" != "/none" ]]; then
        HEALTH_ENABLED="true"
        [[ "$HEALTH_PATH" == /* ]] || HEALTH_PATH="/$HEALTH_PATH"
    else
        HEALTH_ENABLED="false"
    fi

    # ----------------------------------------------------------
    # System preparation
    # ----------------------------------------------------------

    log "🛠️ SYSTEM PREPARATION"

    if ask_yes_no "Run apt update/upgrade?" "n"; then
        apt-get update -y
        apt-get upgrade -y
    fi

    if ! command_exists nginx; then
        if ask_yes_no "Nginx is not installed. Install it now?" "y"; then
            apt-get update -y
            apt-get install -y nginx
        else
            fail "Nginx is required."
        fi
    fi

    # ----------------------------------------------------------
    # Docker installation
    # ----------------------------------------------------------

    log "🐳 DOCKER SETUP"

    if ! command_exists docker; then
        if ask_yes_no "Docker is not installed. Install Docker now?" "y"; then
            apt-get update -y
            apt-get install -y docker.io
            systemctl enable --now docker
        else
            fail "Docker is required for TNIX v2."
        fi
    else
        success "Docker is already installed."
    fi

    systemctl enable --now docker

    if ! docker compose version >/dev/null 2>&1; then
        info "Docker Compose plugin not detected. Installing docker-compose-plugin..."
        apt-get update -y
        apt-get install -y docker-compose-plugin || true
    fi

    if ! docker compose version >/dev/null 2>&1; then
        fail "Docker Compose v2 plugin is required. Install it manually and rerun TNIX."
    fi

    DOCKER_VERSION="$(docker --version)"
    COMPOSE_VERSION="$(docker compose version)"
    success "$DOCKER_VERSION"
    success "$COMPOSE_VERSION"

    # ----------------------------------------------------------
    # Environment file
    # ----------------------------------------------------------

    log "🔐 APPLICATION ENVIRONMENT"

    if [[ -f "$ENV_FILE" ]]; then
        success "Existing .env found: $ENV_FILE"
        chmod 600 "$ENV_FILE"
    else
        touch "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        warn "Created empty environment file: $ENV_FILE"
        info "Add production secrets before starting the application."
    fi

    # ----------------------------------------------------------
    # Dockerfile generation
    # ----------------------------------------------------------

    log "📦 DOCKER IMAGE CONFIGURATION"

    if [[ "$BUILD_LOCAL" == "true" && ! -f "$DOCKERFILE" ]]; then
        info "Generating Dockerfile..."

        cat > "$DOCKERFILE" <<EOF_DOCKERFILE
    FROM python:3.13-slim

    ENV PYTHONDONTWRITEBYTECODE=1 \\
        PYTHONUNBUFFERED=1 \\
        PIP_NO_CACHE_DIR=1

    WORKDIR /app

    RUN apt-get update \\
        && apt-get install -y --no-install-recommends curl ca-certificates \\
        && rm -rf /var/lib/apt/lists/*

    COPY requirements.txt .

    RUN pip install --upgrade pip \\
        && pip install -r requirements.txt

    COPY . .

    RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin appuser \\
        && chown -R appuser:appuser /app

    USER appuser

    EXPOSE $APP_PORT

    CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:$APP_PORT", "$APP_MODULE"]
EOF_DOCKERFILE

        success "Dockerfile created: $DOCKERFILE"
    fi

    if [[ "$BUILD_LOCAL" == "true" && ! -f "$DOCKERIGNORE" ]]; then
        cat > "$DOCKERIGNORE" <<'EOF_DOCKERIGNORE'
    .git
    .gitignore
    .github
    .venv
    venv
    env
    __pycache__
    *.pyc
    *.pyo
    *.pyd
    .pytest_cache
    .mypy_cache
    .ruff_cache
    .coverage
    htmlcov
    .env
    .env.*
    node_modules
    Dockerfile
    docker-compose*.yml
    *.log
EOF_DOCKERIGNORE
        success ".dockerignore created."
    fi

    # ----------------------------------------------------------
    # Docker Compose generation
    # ----------------------------------------------------------

    log "🧩 GENERATING DOCKER COMPOSE"

    if [[ "$BUILD_LOCAL" == "true" ]]; then
        BUILD_BLOCK=$(cat <<EOF_BUILD_BLOCK
        build:
          context: $PROJECT_DIR
          dockerfile: Dockerfile
EOF_BUILD_BLOCK
    )
    else
        BUILD_BLOCK=""
    fi

    if [[ "$HEALTH_ENABLED" == "true" ]]; then
        HEALTH_BLOCK=$(cat <<EOF_HEALTH_BLOCK
        healthcheck:
          test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$APP_PORT$HEALTH_PATH', timeout=5)"]
          interval: 30s
          timeout: 5s
          retries: 3
          start_period: 20s
EOF_HEALTH_BLOCK
    )
    else
        HEALTH_BLOCK=""
    fi

    cat > "$COMPOSE_FILE" <<EOF_COMPOSE
    services:
      app:
        image: ${IMAGE_NAME}:${IMAGE_TAG}
    ${BUILD_BLOCK}    container_name: ${CONTAINER_NAME}
        restart: unless-stopped
        env_file:
          - ${ENV_FILE}
        ports:
          - "127.0.0.1:${APP_PORT}:${APP_PORT}"
        init: true
    ${HEALTH_BLOCK}
EOF_COMPOSE

    success "Compose file created: $COMPOSE_FILE"

    # Validate compose syntax before doing anything else.
    docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" config >/dev/null
    success "Docker Compose configuration is valid."

    # ----------------------------------------------------------
    # Build or pull image
    # ----------------------------------------------------------

    log "🏗️ PREPARING DOCKER IMAGE"

    cd "$DEPLOY_DIR"

    if [[ "$BUILD_LOCAL" == "true" ]]; then
        info "Building ${IMAGE_NAME}:${IMAGE_TAG} ..."
        docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" build --pull
        success "Docker image built successfully."
    else
        info "Pulling ${IMAGE_NAME}:${IMAGE_TAG} ..."
        docker pull "${IMAGE_NAME}:${IMAGE_TAG}"
        success "Docker image pulled successfully."
    fi

    # ----------------------------------------------------------
    # Docker systemd service
    # ----------------------------------------------------------

    log "⚙️ CREATING SYSTEMD SERVICE"

    cat > "$SYSTEMD_SERVICE" <<EOF_SYSTEMD
    [Unit]
    Description=TNIX Docker application - ${SERVICE_NAME}
    Requires=docker.service
    After=docker.service network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    WorkingDirectory=${DEPLOY_DIR}

    ExecStart=/usr/bin/docker compose -p ${COMPOSE_PROJECT} -f ${COMPOSE_FILE} up -d --remove-orphans
    ExecStop=/usr/bin/docker compose -p ${COMPOSE_PROJECT} -f ${COMPOSE_FILE} down
    ExecReload=/usr/bin/docker compose -p ${COMPOSE_PROJECT} -f ${COMPOSE_FILE} up -d --remove-orphans

    TimeoutStartSec=0
    TimeoutStopSec=120

    [Install]
    WantedBy=multi-user.target
EOF_SYSTEMD

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    # ----------------------------------------------------------
    # Start application
    # ----------------------------------------------------------

    log "🚀 STARTING DOCKER APPLICATION"

    systemctl restart "$SERVICE_NAME"
    sleep 3

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        success "Systemd service ${SERVICE_NAME} is active."
    else
        echo ""
        echo "❌ ${SERVICE_NAME} service failed."
        systemctl status "$SERVICE_NAME" --no-pager || true
        journalctl -u "$SERVICE_NAME" --no-pager -n 50 || true
        exit 1
    fi

    # ----------------------------------------------------------
    # Container validation
    # ----------------------------------------------------------

    log "🧪 CHECKING CONTAINER"

    if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
        success "Container ${CONTAINER_NAME} is running."
    else
        echo "❌ Container ${CONTAINER_NAME} is not running."
        docker ps -a --filter "name=^${CONTAINER_NAME}$" || true
        docker logs "$CONTAINER_NAME" --tail 50 2>&1 || true
        exit 1
    fi

    if [[ "$HEALTH_ENABLED" == "true" ]]; then
        info "Waiting for container health check..."
        for _ in {1..20}; do
            STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
            case "$STATUS" in
                healthy)
                    success "Container health check passed."
                    break
                    ;;
                unhealthy)
                    warn "Container health check reported unhealthy."
                    docker logs "$CONTAINER_NAME" --tail 50 2>&1 || true
                    exit 1
                    ;;
                no-healthcheck)
                    warn "No Docker health status available."
                    break
                    ;;
            esac
            sleep 2
        done
    fi

    # ----------------------------------------------------------
    # Nginx configuration
    # ----------------------------------------------------------

    log "🌐 CREATING NGINX CONFIGURATION"

    cat > "$NGINX_CONF" <<EOF_NGINX
    server {
        listen 80;
        listen [::]:80;

        server_name ${NGINX_SERVER_NAMES};

        client_max_body_size 100M;

        location / {
            proxy_pass http://127.0.0.1:${APP_PORT};

            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }
EOF_NGINX

    ln -sfn "$NGINX_CONF" "$NGINX_LINK"

    # Important for multi-app VPS setups: do NOT remove the default site or
    # other existing applications. TNIX v2 only manages its own site.

    log "🧪 TESTING NGINX CONFIGURATION"

    if nginx -t; then
        success "Nginx configuration successful."
    else
        echo ""
        echo "❌ Nginx configuration failed."
        nginx -t || true
        exit 1
    fi

    systemctl enable nginx
    systemctl reload nginx
    success "Nginx reloaded successfully."

    # ----------------------------------------------------------
    # Firewall
    # ----------------------------------------------------------

    log "🔥 CONFIGURING FIREWALL (UFW)"

    if ask_yes_no "Install/configure UFW firewall?" "y"; then
        apt-get install -y ufw

        # SSH first to avoid accidentally locking yourself out.
        ufw allow OpenSSH || ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp

        if ask_yes_no "Enable UFW firewall now?" "n"; then
            ufw --force enable
            success "UFW enabled."
        else
            warn "UFW installed but not enabled."
        fi

        ufw status
    else
        warn "UFW configuration skipped."
    fi

    # ----------------------------------------------------------
    # SSL
    # ----------------------------------------------------------

    log "🔒 HTTPS SSL SETUP"

    if ask_yes_no "Generate/renew SSL certificate with Certbot?" "y"; then
        if ! command_exists certbot; then
            info "Installing Certbot and the Nginx plugin..."
            apt-get update -y
            apt-get install -y certbot python3-certbot-nginx
        fi

        certbot --nginx \
            "${CERTBOT_DOMAINS[@]}" \
            --non-interactive \
            --agree-tos \
            -m "$SSL_EMAIL" \
            --redirect

        certbot renew --dry-run
        success "SSL setup completed."
    else
        warn "SSL setup skipped."
    fi

    # ----------------------------------------------------------
    # Final verification
    # ----------------------------------------------------------

    log "🔍 FINAL VERIFICATION"

    systemctl --no-pager --full status "$SERVICE_NAME" || true

    echo ""
    docker ps --filter "name=^${CONTAINER_NAME}$"

    echo ""
    ss -tulpn | grep -E ":(80|443)\\b" || true

    # ----------------------------------------------------------
    # Summary
    # ----------------------------------------------------------

    log "🎉 TNIX V2 DEPLOYMENT COMPLETE"

    echo ""
    echo "🌍 Domain:           https://${DOMAIN}"
    echo "📂 Project:          ${PROJECT_DIR}"
    echo "⚙️ Service:           ${SERVICE_NAME}"
    echo "🐳 Container:         ${CONTAINER_NAME}"
    echo "🖼️ Image:             ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "🔌 Internal port:     127.0.0.1:${APP_PORT}"
    echo "📄 Compose:           ${COMPOSE_FILE}"
    echo "🔐 Environment:       ${ENV_FILE}"
    echo "🧾 Systemd unit:      ${SYSTEMD_SERVICE}"
    echo "🌐 Nginx config:      ${NGINX_CONF}"

    echo ""
    echo "=================================================="
    echo "📋 MANAGEMENT COMMANDS"
    echo "=================================================="

    echo ""
    echo "Service status:"
    echo "  systemctl status ${SERVICE_NAME}"
    echo ""
    echo "Restart application:"
    echo "  systemctl restart ${SERVICE_NAME}"
    echo ""
    echo "Stop application:"
    echo "  systemctl stop ${SERVICE_NAME}"
    echo ""
    echo "Application logs:"
    echo "  docker logs -f ${CONTAINER_NAME}"
    echo ""
    echo "Docker status:"
    echo "  docker ps"
    echo ""
    echo "Compose status:"
    echo "  docker compose -p ${COMPOSE_PROJECT} -f ${COMPOSE_FILE} ps"
    echo ""
    echo "Pull latest image and restart:"
    echo "  docker compose -p ${COMPOSE_PROJECT} -f ${COMPOSE_FILE} pull"
    echo "  systemctl restart ${SERVICE_NAME}"
    echo ""
    echo "Rebuild local image and restart:"
    echo "  docker compose -p ${COMPOSE_PROJECT} -f ${COMPOSE_FILE} build --pull"
    echo "  systemctl restart ${SERVICE_NAME}"
    echo ""
    echo "Nginx config test:"
    echo "  nginx -t"
    echo ""
    echo "Restart Nginx:"
    echo "  systemctl reload nginx"
    echo ""
    echo "Open ports:"
    echo "  ss -tulpn"
    echo ""
    echo "Firewall rules:"
    echo "  ufw status"
    echo ""
    echo "🚀 TNIX v2 deployment completed successfully!"
    echo ""
}

run_bare_metal() {
    # ==========================================================
    # USER INPUTS
    # ==========================================================

    read -p "Enter domain name: " DOMAIN

    read -p "Enter project root path: " PROJECT_DIR

    read -p "Enter Flask app module (example app:app): " APP_MODULE

    read -p "Enter service name [default: tnixapp]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-tnixapp}

    read -p "Enter static folder path [default: $PROJECT_DIR/static]: " STATIC_PATH
    STATIC_PATH=${STATIC_PATH:-$PROJECT_DIR/static}

    echo ""
    echo "=================================================="
    echo "🐍 PYTHON VIRTUAL ENVIRONMENT"
    echo "=================================================="

    read -p "Do you already have a virtual environment? (y/n): " HAS_VENV

    if [[ "$HAS_VENV" == "y" || "$HAS_VENV" == "Y" ]]; then
        read -p "Enter virtual environment path: " VENV_PATH
    else
        read -p "Enter path to create virtual environment: " VENV_PATH

        echo ""
        echo "📦 Creating virtual environment..."

        python3 -m venv $VENV_PATH

        source $VENV_PATH/bin/activate

        read -p "Install requirements.txt packages? (y/n): " INSTALL_REQS

        if [[ "$INSTALL_REQS" == "y" || "$INSTALL_REQS" == "Y" ]]; then

            if [ -f "$PROJECT_DIR/requirements.txt" ]; then
                pip install -r $PROJECT_DIR/requirements.txt
            else
                echo "⚠️ requirements.txt not found."
            fi
        fi
    fi

    SOCK_FILE="/run/${SERVICE_NAME}.sock"
    NGINX_CONF="/etc/nginx/sites-available/${SERVICE_NAME}"
    SYSTEMD_SERVICE="/etc/systemd/system/${SERVICE_NAME}.service"

    echo ""
    echo "=================================================="
    echo "🛠️ SYSTEM PREPARATION"
    echo "=================================================="

    read -p "Run apt update/upgrade? (y/n): " RUN_UPDATE

    if [[ "$RUN_UPDATE" == "y" || "$RUN_UPDATE" == "Y" ]]; then

        apt update -y
        apt upgrade -y

    fi

    read -p "Install nginx? (y/n): " INSTALL_NGINX

    if [[ "$INSTALL_NGINX" == "y" || "$INSTALL_NGINX" == "Y" ]]; then

        apt install nginx -y

    fi

    read -p "Install certbot + nginx plugin? (y/n): " INSTALL_CERTBOT

    if [[ "$INSTALL_CERTBOT" == "y" || "$INSTALL_CERTBOT" == "Y" ]]; then

        apt install certbot python3-certbot-nginx -y

    fi

    echo ""
    echo "=================================================="
    echo "📁 SETTING PERMISSIONS"
    echo "=================================================="

    chmod -R 755 $PROJECT_DIR || true

    echo ""
    echo "=================================================="
    echo "⚙️ CREATING SYSTEMD SERVICE"
    echo "=================================================="

    cat > $SYSTEMD_SERVICE <<EOF
    [Unit]
    Description=Gunicorn instance for ${SERVICE_NAME}
    After=network.target

    [Service]
    User=root
    Group=www-data
    WorkingDirectory=${PROJECT_DIR}
    Environment="PATH=${VENV_PATH}/bin"

    ExecStart=${VENV_PATH}/bin/gunicorn \
        --workers 3 \
        --bind unix:${SOCK_FILE} \
        ${APP_MODULE}

    Restart=always

    [Install]
    WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}

    echo ""
    echo "=================================================="
    echo "🧪 CHECKING GUNICORN SERVICE"
    echo "=================================================="

    if systemctl is-active --quiet ${SERVICE_NAME}; then

        echo "✅ ${SERVICE_NAME} service is running."

    else

        echo "❌ ${SERVICE_NAME} service failed."

        journalctl -u ${SERVICE_NAME} --no-pager -n 30

        exit 1

    fi

    echo ""
    echo "=================================================="
    echo "🌐 CREATING NGINX CONFIG"
    echo "=================================================="

    cat > $NGINX_CONF <<EOF
    server {
        listen 80;
        server_name ${DOMAIN} www.${DOMAIN};

        client_max_body_size 100M;

        location /static {
            alias ${STATIC_PATH};
        }

        location / {
            include proxy_params;
            proxy_pass http://unix:${SOCK_FILE};
        }
    }
EOF

    ln -sf $NGINX_CONF /etc/nginx/sites-enabled/

    if [ -f /etc/nginx/sites-enabled/default ]; then
        rm /etc/nginx/sites-enabled/default
    fi

    echo ""
    echo "=================================================="
    echo "🧪 TESTING NGINX CONFIGURATION"
    echo "=================================================="

    if nginx -t; then

        echo "✅ Nginx configuration successful."

    else

        echo ""
        echo "❌ Nginx configuration failed."

        if [ ! -f "/etc/nginx/nginx.conf" ]; then

            echo ""
            echo "⚠️ Missing nginx.conf detected."
            echo "⚠️ Nginx installation appears corrupted."

            read -p "Purge and reinstall nginx automatically? (y/n): " FIX_NGINX

            if [[ "$FIX_NGINX" == "y" || "$FIX_NGINX" == "Y" ]]; then

                echo ""
                echo "🧹 Purging nginx..."

                apt remove nginx nginx-common -y || true
                apt purge nginx nginx-common -y || true
                apt autoremove -y || true

                echo ""
                echo "📦 Reinstalling nginx..."

                apt update -y
                apt install nginx -y

                echo ""
                echo "🔁 Recreating nginx config..."

                cat > $NGINX_CONF <<EOF
    server {
        listen 80;
        server_name ${DOMAIN} www.${DOMAIN};

        client_max_body_size 100M;

        location /static {
            alias ${STATIC_PATH};
        }

        location / {
            include proxy_params;
            proxy_pass http://unix:${SOCK_FILE};
        }
    }
EOF

                ln -sf $NGINX_CONF /etc/nginx/sites-enabled/

                nginx -t

            else

                echo "❌ Deployment stopped."
                exit 1

            fi

        else

            echo ""
            echo "❌ Unknown nginx configuration error."
            exit 1

        fi
    fi

    echo ""
    echo "=================================================="
    echo "🚫 CHECKING PORT 80 CONFLICTS"
    echo "=================================================="

    PORT_SERVICE=$(lsof -i :80 -t 2>/dev/null | head -n 1)

    if [ ! -z "$PORT_SERVICE" ]; then

        SERVICE_NAME_PORT=$(ps -p $PORT_SERVICE -o comm=)

        echo ""
        echo "⚠️ Port 80 is currently being used by:"
        echo "➡️ $SERVICE_NAME_PORT (PID: $PORT_SERVICE)"

        read -p "Stop this service/process automatically? (y/n): " STOP_PORT_SERVICE

        if [[ "$STOP_PORT_SERVICE" == "y" || "$STOP_PORT_SERVICE" == "Y" ]]; then

            echo ""
            echo "🛑 Stopping process using port 80..."

            kill -9 $PORT_SERVICE || true

            sleep 2

            echo "✅ Port 80 cleaned."

        else

            echo ""
            echo "⚠️ Port cleanup skipped."

        fi

    else

        echo ""
        echo "✅ Port 80 is free."

    fi

    echo ""
    echo "=================================================="
    echo "🚀 STARTING NGINX"
    echo "=================================================="

    systemctl restart nginx
    systemctl enable nginx

    echo ""
    echo "=================================================="
    echo "🔍 VERIFYING NGINX"
    echo "=================================================="

    if systemctl is-active --quiet nginx; then

        echo "✅ Nginx is running successfully."

    else

        echo "❌ Nginx failed to start."

        echo ""
        systemctl status nginx --no-pager

        echo ""
        journalctl -xeu nginx.service --no-pager -n 30

        exit 1

    fi

    echo ""
    echo "=================================================="
    echo "🔥 CONFIGURING FIREWALL (UFW)"
    echo "=================================================="

    read -p "Install UFW firewall? (y/n): " INSTALL_UFW

    if [[ "$INSTALL_UFW" == "y" || "$INSTALL_UFW" == "Y" ]]; then

        apt install ufw -y

        echo ""
        echo "🔓 Allowing OpenSSH..."
        ufw allow OpenSSH

        echo ""
        echo "🔓 Allowing Port 22..."
        ufw allow 22/tcp

        echo ""
        echo "🔓 Allowing Full Nginx Access..."
        ufw allow 'Nginx Full'

        echo ""
        read -p "Enable UFW firewall now? (y/n): " ENABLE_UFW

        if [[ "$ENABLE_UFW" == "y" || "$ENABLE_UFW" == "Y" ]]; then

            ufw --force enable

            echo ""
            echo "✅ UFW enabled successfully."

            echo ""
            echo "📋 Firewall Rules:"
            ufw status

        else

            echo ""
            echo "⚠️ UFW installed but not enabled."

        fi

    else

        echo ""
        echo "⚠️ UFW setup skipped."

    fi

    echo ""
    echo "=================================================="
    echo "🔒 HTTPS SSL SETUP"
    echo "=================================================="

    read -p "Generate SSL certificate with certbot? (y/n): " RUN_CERTBOT

    if [[ "$RUN_CERTBOT" == "y" || "$RUN_CERTBOT" == "Y" ]]; then

        read -p "Enter email for SSL notifications: " SSL_EMAIL

        echo ""
        echo "🚀 Generating SSL certificate..."

        certbot --nginx \
            -d ${DOMAIN} \
            -d www.${DOMAIN} \
            --non-interactive \
            --agree-tos \
            -m ${SSL_EMAIL} \
            --redirect

        echo ""
        echo "🧪 Testing SSL auto renewal..."

        certbot renew --dry-run

        echo ""
        echo "✅ SSL setup completed."

    else

        echo ""
        echo "⚠️ SSL setup skipped."

    fi

    echo ""
    echo "=================================================="
    echo "🎉 DEPLOYMENT COMPLETE"
    echo "=================================================="

    echo ""
    echo "🌍 Domain: https://${DOMAIN}"
    echo "📂 Project: ${PROJECT_DIR}"
    echo "⚙️ Service: ${SERVICE_NAME}"
    echo "🐍 Virtual Environment: ${VENV_PATH}"

    echo ""
    echo "=================================================="
    echo "📋 USEFUL COMMANDS"
    echo "=================================================="

    echo ""
    echo "Restart Flask App:"
    echo "systemctl restart ${SERVICE_NAME}"

    echo ""
    echo "View Flask Logs:"
    echo "journalctl -u ${SERVICE_NAME} -f"

    echo ""
    echo "Restart Nginx:"
    echo "systemctl restart nginx"

    echo ""
    echo "Test Nginx Config:"
    echo "nginx -t"

    echo ""
    echo "Check Open Ports:"
    echo "ss -tulpn"

    echo ""
    echo "🔥 Firewall Rules:"
    echo "ufw status"

    echo ""
    echo "🚀 TNIX deployment completed successfully!"
    echo ""
}

case "$DEPLOYMENT_TYPE" in
    1)
        run_docker
        ;;
    2)
        run_bare_metal
        ;;
esac
