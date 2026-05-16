#!/bin/bash

# ==========================================================
# ████████╗███╗   ██╗██╗██╗  ██╗
# ╚══██╔══╝████╗  ██║██║╚██╗██╔╝
#    ██║   ██╔██╗ ██║██║ ╚███╔╝
#    ██║   ██║╚██╗██║██║ ██╔██╗
#    ██║   ██║ ╚████║██║██╔╝ ██╗
#    ╚═╝   ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝
#
#                T N I X
#      Flask + Gunicorn + Nginx + SSL
# ==========================================================

set -e

clear

echo ""
echo "████████╗███╗   ██╗██╗██╗  ██╗"
echo "╚══██╔══╝████╗  ██║██║╚██╗██╔╝"
echo "   ██║   ██╔██╗ ██║██║ ╚███╔╝ "
echo "   ██║   ██║╚██╗██║██║ ██╔██╗ "
echo "   ██║   ██║ ╚████║██║██╔╝ ██╗"
echo "   ╚═╝   ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝"
echo ""
echo "🚀 Flask VPS Deployment Wizard"
echo "🌍 Gunicorn + Nginx + HTTPS"
echo ""

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

read -p "Install/Reinstall nginx? (y/n): " INSTALL_NGINX

if [[ "$INSTALL_NGINX" == "y" || "$INSTALL_NGINX" == "Y" ]]; then

    echo ""
    echo "📦 Installing nginx..."

    apt install nginx -y
fi

read -p "Install certbot + nginx plugin? (y/n): " INSTALL_CERTBOT

if [[ "$INSTALL_CERTBOT" == "y" || "$INSTALL_CERTBOT" == "Y" ]]; then

    echo ""
    echo "📦 Installing certbot..."

    apt install certbot python3-certbot-nginx -y
fi

echo ""
echo "=================================================="
echo "📁 PERMISSIONS"
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
    echo ""
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
echo "🚫 CLEARING PORT 80 CONFLICTS"
echo "=================================================="

systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true

pkill nginx 2>/dev/null || true

echo "✅ Port conflicts cleared."

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
echo "🚀 TNIX deployment completed successfully!"
echo ""
