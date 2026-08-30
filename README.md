![TNIX Banner](https://raw.githubusercontent.com/TaqsBlaze/tnix/main/image/image.png)

# TNIX

**Automated Flask VPS deployment toolkit for production-ready Python applications.**

TNIX is an interactive Linux VPS deployment wizard for Flask applications. TNIX v2 supports both **Docker-based** and **bare-metal** deployments while keeping Nginx, HTTPS, and systemd configuration simple and repeatable.

```text
                         TNIX v2

                ┌─────────────────────┐
                │  Deployment Type    │
                └──────────┬──────────┘
                           │
                 ┌─────────┴─────────┐
                 │                   │
                 ▼                   ▼
             🐳 Docker          🐍 Bare Metal
                 │                   │
                 ▼                   ▼
          Docker Compose         Python venv
                 │                   │
                 ▼                   ▼
             systemd              Gunicorn
                 │                   │
                 └─────────┬─────────┘
                           ▼
                        Nginx
                           │
                           ▼
                       HTTPS/SSL
```

TNIX is designed for developers who want to deploy Flask applications to Linux VPS servers in minutes instead of manually configuring application servers, reverse proxies, services, and SSL.

---

## What's New in TNIX v2

TNIX v2 introduces a deployment type selector at startup:

```text
1) Docker
2) Bare Metal
```

### Docker deployment

Docker mode runs the application as a Docker container managed through Docker Compose and systemd:

```text
Project
   ↓
Dockerfile
   ↓
Docker Image
   ↓
Docker Compose
   ↓
systemd
   ↓
Nginx
   ↓
HTTPS
```

Docker mode supports:

- Docker installation and validation
- Docker Compose v2 validation
- Local Docker image builds
- Existing Docker images from a registry
- Generated Dockerfile when one does not exist
- Generated `docker-compose.yml`
- Application `.env` file with restrictive permissions
- Non-root application user inside the generated container
- Container restart policy
- Optional HTTP health checks
- systemd service management
- Nginx reverse proxy configuration
- UFW firewall configuration
- Certbot HTTPS/SSL setup
- Deployment verification and container checks

### Bare-metal deployment

Bare-metal mode preserves the original TNIX workflow:

```text
Project
   ↓
Python Virtual Environment
   ↓
Gunicorn
   ↓
systemd
   ↓
Unix Socket
   ↓
Nginx
   ↓
HTTPS
```

This mode is useful for existing projects that are not yet containerized.

---

## Features

### Deployment

- ⚡ Interactive Flask VPS deployment wizard
- 🐳 Docker deployment support
- 🐍 Bare-metal Flask deployment
- 📦 Local Docker image builds
- 📥 Pull existing Docker images
- 🧩 Automatic Docker Compose configuration
- 🛠 Automatic Dockerfile generation
- 🔄 Automatic service startup and restart
- 🔁 Auto-start applications after reboot

### Web Server

- 🌐 Nginx reverse proxy configuration
- 🔒 HTTPS/SSL with Certbot
- 🔀 Application routing
- 📁 Static file routing in bare-metal mode
- 🧪 Nginx configuration validation

### Infrastructure

- ⚙️ systemd service management
- 🔥 UFW firewall configuration
- 🐳 Docker service management
- 🩺 Container health-check support
- 🔍 Deployment verification
- 🛡️ Safe multi-application Nginx handling in Docker mode

### Developer Experience

- 📋 Interactive configuration
- ✅ Input validation
- 📜 Useful management commands printed after deployment
- 🚨 Better Bash error handling in Docker mode
- 🧹 Minimal manual VPS configuration

---

## Requirements

TNIX is designed primarily for Ubuntu/Debian-based Linux VPS servers.

Recommended:

- Linux VPS
- `sudo` / root access
- A registered domain pointing to the VPS
- Flask application
- `requirements.txt`

For Docker deployments:

- Docker is installed automatically when requested
- Docker Compose v2 is required and checked by TNIX

For bare-metal deployments:

- Python 3 with `venv`
- Gunicorn
- Flask application

---

## Usage

Make the script executable:

```bash
chmod +x tnix-v2.sh
```

Run it as root:

```bash
sudo ./tnix-v2.sh
```

TNIX first asks you to choose the deployment type:

```text
==================================================
🚀 SELECT DEPLOYMENT TYPE
==================================================

1) Docker
   Docker image + Docker Compose + systemd

2) Bare Metal
   Original Flask + Gunicorn + Python venv + systemd

Select deployment type [1-2]:
```

---

## Docker Workflow

Select:

```text
1) Docker
```

TNIX asks for the application's domain, project directory, Flask module, service name, application port, image name/tag, image build preference, health-check path, and SSL configuration.

Example values:

```text
Domain:             dev.ndini.co.zw
Project:            /home/developer/dev
Flask module:       app:app
Service:            ndini-dev
Application port:   8000
Image:              ndini-dev
Tag:                latest
```

TNIX then creates/configures:

```text
/home/developer/dev/
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
└── .env
```

The generated systemd unit manages Docker Compose instead of running Gunicorn directly:

```text
systemd
   ↓
docker compose
   ↓
Ndini container
```

Useful commands:

```bash
systemctl status ndini-dev
systemctl restart ndini-dev
systemctl stop ndini-dev
docker logs -f ndini-dev
docker ps
docker compose -p ndini-dev ps
```

---

## Using an Existing Registry Image

Docker mode can use an image that already exists in a container registry.

Set:

```text
Build Docker image locally? → n
```

TNIX will pull the configured image and run it through Docker Compose.

Example:

```text
ghcr.io/your-org/ndini:latest
```

This makes Docker mode suitable for a CI/CD workflow where GitHub Actions builds and pushes images and the VPS only pulls and runs them.

---

## Health Checks

Docker deployments can optionally configure an HTTP health-check endpoint.

Default:

```text
/health
```

TNIX checks:

```text
http://127.0.0.1:<PORT>/health
```

Example Flask endpoint:

```python
@app.get("/health")
def health():
    return {"status": "healthy"}
```

Use `none` when the application does not have a health endpoint.

---

## Bare-Metal Workflow

Select:

```text
2) Bare Metal
```

TNIX uses the original deployment model:

```text
Python venv
   ↓
Gunicorn
   ↓
systemd
   ↓
Unix socket
   ↓
Nginx
   ↓
HTTPS
```

You can use an existing virtual environment or allow TNIX to create one and optionally install `requirements.txt`.

Useful commands:

```bash
systemctl status <service>
systemctl restart <service>
journalctl -u <service> -f
```

---

## Nginx

TNIX creates a dedicated Nginx site configuration for each application.

Docker mode proxies to the application's local Docker-published port:

```text
Nginx
  ↓
127.0.0.1:<application-port>
  ↓
Docker container
```

Applications can therefore share the same VPS while using different domains and ports.

Example:

```text
ndini.co.zw       → production
test.ndini.co.zw  → test
dev.ndini.co.zw   → development
```

Each deployment can have its own:

```text
Project directory
Service
Container
Port
Environment file
Nginx configuration
```

---

## SSL / HTTPS

TNIX can install and configure Certbot with the Nginx plugin.

It can:

- Generate certificates
- Configure HTTPS
- Redirect HTTP to HTTPS
- Test certificate renewal

Example:

```bash
certbot renew --dry-run
```

---

## Firewall

TNIX can install and configure UFW.

The Docker deployment opens:

```text
22/tcp
80/tcp
443/tcp
```

The application port is bound to `127.0.0.1` by default in Docker mode, keeping it inaccessible directly from the public internet.

---

## Security Notes

For production deployments:

- Keep secrets in the application's `.env` file rather than committing them to Git.
- Docker mode creates the `.env` file with restrictive permissions.
- Generated Docker containers run the application as a non-root user.
- Do not expose application ports publicly unless there is a specific reason.
- Use HTTPS in production.
- Use separate environments and databases for development, testing, and production.
- For commercial deployments, prefer immutable image tags such as a Git commit SHA instead of `latest`.

---

## Example Multi-Environment VPS

TNIX can be used to host multiple application environments on one VPS:

```text
/home/developer/
├── production/
├── test/
└── dev/
```

Example:

```text
Production
domain:   ndini.co.zw
port:     8000
service:  ndini-production

Test
domain:   test.ndini.co.zw
port:     8001
service:  ndini-test

Development
domain:   dev.ndini.co.zw
port:     8002
service:  ndini-dev
```

This provides a simple path toward a commercial CI/CD setup without requiring Kubernetes or other complex orchestration.

---

## Tech Stack

### Core

- Bash
- Linux
- systemd
- Nginx
- Certbot
- UFW

### Docker Mode

- Docker
- Docker Compose v2
- Docker images
- Gunicorn
- Python

### Bare-Metal Mode

- Python
- Flask
- Gunicorn
- Python virtual environments

---

## Use Cases

TNIX is suitable for:

- Flask applications
- SaaS applications
- Startup MVPs
- Internal business systems
- API servers
- Production VPS deployments
- Multi-environment deployments
- Containerized Flask applications
- Existing bare-metal Flask applications

---

## Target Platforms

TNIX is intended for most Ubuntu/Debian-based VPS providers, including:

- DigitalOcean
- Hetzner
- AWS EC2
- Azure VPS
- Linode
- Vultr
- Oracle Cloud
- Contabo
- Self-hosted Linux servers

---

## CI/CD Direction

TNIX v2 is designed to fit into a modern CI/CD pipeline.

Recommended flow:

```text
Developer
   ↓
GitHub
   ↓
CI / Security Checks
   ↓
Build Docker Image
   ↓
Container Registry
   ↓
Production VPS
   ↓
Docker Compose
   ↓
systemd
   ↓
Application
```

For example:

```text
GitHub Actions
      ↓
ghcr.io/organization/app:<git-sha>
      ↓
VPS
      ↓
docker compose pull
      ↓
systemctl restart <service>
```

TNIX handles the server-side provisioning and runtime configuration, while CI/CD can handle image creation and delivery.

---

## Roadmap

- ✅ Docker deployment support
- ✅ Bare-metal deployment support
- ✅ Docker Compose integration
- ✅ systemd management for Docker applications
- ✅ Container health checks
- ⬜ Django deployment support
- ⬜ Node.js deployment support
- ⬜ Domain/DNS verification checks
- ⬜ Improved multi-app management
- ⬜ Monitoring integration
- ⬜ Backup automation
- ⬜ CI/CD integration
- ⬜ Immutable image / release management
- ⬜ Deployment rollback support

---

## License

MIT License

Built for developers who ship fast. 🚀
