#!/usr/bin/env python3
"""
TNIX v2 - Flask VPS Deployment Wizard

Translated from the TNIX v2 Bash deployment script.

Deployment modes:
    1) Docker     - Docker image + Compose + systemd + Nginx + HTTPS
    2) Bare Metal - Python venv + Gunicorn + systemd + Nginx + HTTPS

The script intentionally keeps host-level operations (APT, systemd, Nginx,
UFW, Certbot, Docker) in Python while generating configuration files with
explicit string formatting so generated YAML/INI/Nginx configuration remains
well-formed and readable.
"""

from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import sys
import textwrap
import time
from pathlib import Path
from typing import Iterable, Sequence


# ==========================================================
# Constants
# ==========================================================

DEFAULT_SERVICE_NAME = "tnixapp"
DEFAULT_APP_PORT = 8000
DEFAULT_HEALTH_PATH = "/health"


# ==========================================================
# Terminal helpers
# ==========================================================

def clear_screen() -> None:
    try:
        subprocess.run(["clear"], check=False)
    except Exception:
        pass


def banner() -> None:
    print("")
    print("████████╗███╗   ██╗██╗██╗  ██╗")
    print("╚══██╔══╝████╗  ██║██║╚██╗██╔╝")
    print("   ██║   ██╔██╗ ██║██║ ╚███╔╝ ")
    print("   ██║   ██║╚██╗██║██║ ██╔██╗ ")
    print("   ██║   ██║ ╚████║██║██╔╝ ██╗")
    print("   ╚═╝   ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝")
    print("")
    print("🚀 Flask VPS Deployment Wizard")
    print("🐳 Docker or 🐍 Bare Metal")
    print("🌍 Nginx + HTTPS")
    print("")


def section(title: str) -> None:
    print("")
    print("=" * 50)
    print(title)
    print("=" * 50)


def info(message: str) -> None:
    print(f"➡️  {message}")


def success(message: str) -> None:
    print(f"✅ {message}")


def warn(message: str) -> None:
    print(f"⚠️  {message}")


def fail(message: str, exit_code: int = 1) -> None:
    print(f"❌ {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def ask(prompt: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default is not None else ""
    value = input(f"{prompt}{suffix}: ").strip()
    return value if value else (default if default is not None else "")


def ask_yes_no(prompt: str, default: bool = True) -> bool:
    suffix = " (Y/n)" if default else " (y/N)"
    while True:
        value = input(f"{prompt}{suffix}: ").strip().lower()
        if not value:
            return default
        if value in {"y", "yes"}:
            return True
        if value in {"n", "no"}:
            return False
        print("Please answer y or n.")


def choose_deployment_type() -> int:
    section("🚀 SELECT DEPLOYMENT TYPE")
    print("")
    print("1) Docker")
    print("   Docker image + Docker Compose + systemd")
    print("")
    print("2) Bare Metal")
    print("   Original Flask + Gunicorn + Python venv + systemd")
    print("")

    while True:
        value = input("Select deployment type [1-2]: ").strip()
        if value in {"1", "2"}:
            return int(value)
        print("❌ Invalid selection. Please choose 1 or 2.")


# ==========================================================
# Command helpers
# ==========================================================

def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def require_root() -> None:
    if os.geteuid() != 0:
        fail("Run TNIX as root (sudo python3 tnix-v2.py).")


def run(
    command: Sequence[str],
    *,
    check: bool = True,
    capture: bool = False,
    cwd: str | Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a host command and preserve readable failures."""
    try:
        return subprocess.run(
            list(command),
            check=check,
            cwd=str(cwd) if cwd else None,
            env=env,
            text=True,
            capture_output=capture,
        )
    except FileNotFoundError as exc:
        fail(f"Command not found: {command[0]}")
        raise exc


def output(command: Sequence[str], cwd: str | Path | None = None) -> str:
    result = run(command, capture=True, cwd=cwd)
    return (result.stdout or "").strip()


def install_apt(packages: Iterable[str]) -> None:
    packages = list(packages)
    if not packages:
        return
    run(["apt-get", "update", "-y"])
    run(["apt-get", "install", "-y", *packages])


# ==========================================================
# Validation / sanitization
# ==========================================================

def sanitize_service_name(value: str) -> str:
    """Keep names readable while removing shell/YAML-hostile characters."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9_.-]+", "-", value)
    value = value.strip("-_.")
    return value or DEFAULT_SERVICE_NAME


def compose_project_name(value: str) -> str:
    """Docker Compose project names: lowercase alnum, '-' and '_'."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9_-]+", "-", value)
    value = re.sub(r"[-_]+", "-", value)
    value = value.strip("-_")
    return value or "tnixapp"


def sanitize_image_name(value: str) -> str:
    """Normalize a simple local image name; registry paths are retained."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9._/-]+", "-", value)
    value = value.strip("-_.")
    return value or "tnixapp"


def validate_domain(domain: str) -> bool:
    domain = domain.strip().lower()
    if not domain or "/" in domain or " " in domain:
        return False
    return bool(re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", domain))


def validate_port(port: str) -> int:
    if not port.isdigit():
        fail("APP_PORT must be numeric.")
    value = int(port)
    if not 1024 <= value <= 65535:
        fail("APP_PORT must be between 1024 and 65535.")
    return value


def ensure_absolute_project_dir(path: str) -> Path:
    project = Path(path).expanduser().resolve()
    if not project.is_dir():
        fail(f"Project directory does not exist: {project}")
    return project


def yaml_double_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


# ==========================================================
# Generated configuration
# ==========================================================

def generate_dockerfile(
    *,
    app_port: int,
    app_module: str,
    output_path: Path,
    project_dir: Path,
) -> None:
    content = f'''FROM python:3.13-slim

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

EXPOSE {app_port}

CMD ["gunicorn", "--workers", "3", "--bind", "0.0.0.0:{app_port}", "{app_module}"]
'''
    output_path.write_text(content, encoding="utf-8")


def generate_dockerignore(output_path: Path) -> None:
    content = '''.git
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
'''
    output_path.write_text(content, encoding="utf-8")


def generate_compose(
    *,
    image_name: str,
    image_tag: str,
    container_name: str,
    app_port: int,
    build_local: bool,
    health_path: str | None,
    output_path: Path,
) -> None:
    lines = [
        "services:",
        "  app:",
        f"    image: {yaml_double_quote(f'{image_name}:{image_tag}')}\n",
    ]

    # Remove the intentionally convenient newline so every emitted field has
    # exactly one newline. This keeps the generator deterministic/readable.
    lines = [line.rstrip("\n") for line in lines]

    if build_local:
        lines += [
            "    build:",
            "      context: .",
            "      dockerfile: Dockerfile",
        ]

    lines += [
        f"    container_name: {yaml_double_quote(container_name)}",
        "    restart: unless-stopped",
        "    env_file:",
        "      - .env",
        "    ports:",
        f'      - "127.0.0.1:{app_port}:{app_port}"',
        "    init: true",
    ]

    if health_path:
        health_path = health_path if health_path.startswith("/") else f"/{health_path}"
        health_url = f"http://127.0.0.1:{app_port}{health_path}"
        health_python = (
            "import urllib.request; "
            f"urllib.request.urlopen({health_url!r}, timeout=5)"
        )
        lines += [
            "    healthcheck:",
            "      test:",
            "        - CMD",
            "        - python",
            "        - -c",
            f"        - {yaml_double_quote(health_python)}",
            "      interval: 30s",
            "      timeout: 5s",
            "      retries: 3",
            "      start_period: 20s",
        ]

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def generate_docker_systemd(
    *,
    service_name: str,
    compose_project: str,
    compose_file: Path,
    deploy_dir: Path,
    output_path: Path,
) -> None:
    content = f'''[Unit]
Description=TNIX Docker application - {service_name}
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={deploy_dir}

ExecStart=/usr/bin/docker compose -p {compose_project} -f {compose_file} up -d --remove-orphans
ExecStop=/usr/bin/docker compose -p {compose_project} -f {compose_file} down
ExecReload=/usr/bin/docker compose -p {compose_project} -f {compose_file} up -d --remove-orphans

TimeoutStartSec=0
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
'''
    output_path.write_text(content, encoding="utf-8")


def generate_bare_nginx(
    *,
    domain_names: str,
    static_path: Path,
    socket_file: Path,
    output_path: Path,
) -> None:
    content = f'''server {{
    listen 80;
    listen [::]:80;

    server_name {domain_names};

    client_max_body_size 100M;

    location /static {{
        alias {static_path};
    }}

    location / {{
        include proxy_params;
        proxy_pass http://unix:{socket_file};
    }}
}}
'''
    output_path.write_text(content, encoding="utf-8")


def generate_docker_nginx(
    *,
    domain_names: str,
    app_port: int,
    output_path: Path,
) -> None:
    content = f'''server {{
    listen 80;
    listen [::]:80;

    server_name {domain_names};

    client_max_body_size 100M;

    location / {{
        proxy_pass http://127.0.0.1:{app_port};

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }}
}}
'''
    output_path.write_text(content, encoding="utf-8")


def generate_bare_systemd(
    *,
    service_name: str,
    project_dir: Path,
    venv_path: Path,
    socket_file: Path,
    app_module: str,
    output_path: Path,
) -> None:
    content = f'''[Unit]
Description=Gunicorn instance for {service_name}
After=network.target

[Service]
User=root
Group=www-data
WorkingDirectory={project_dir}
Environment="PATH={venv_path}/bin"

ExecStart={venv_path}/bin/gunicorn \\
    --workers 3 \\
    --bind unix:{socket_file} \\
    {app_module}

Restart=always

[Install]
WantedBy=multi-user.target
'''
    output_path.write_text(content, encoding="utf-8")


# ==========================================================
# Common host setup
# ==========================================================

def prepare_system() -> None:
    section("🛠️ SYSTEM PREPARATION")

    if ask_yes_no("Run apt update/upgrade?", default=False):
        run(["apt-get", "update", "-y"])
        run(["apt-get", "upgrade", "-y"])


def ensure_nginx() -> None:
    if not command_exists("nginx"):
        if ask_yes_no("Nginx is not installed. Install it now?", default=True):
            install_apt(["nginx"])
        else:
            fail("Nginx is required.")


def configure_firewall() -> None:
    section("🔥 CONFIGURING FIREWALL (UFW)")

    if not ask_yes_no("Install/configure UFW firewall?", default=True):
        warn("UFW configuration skipped.")
        return

    install_apt(["ufw"])
    run(["ufw", "allow", "OpenSSH"], check=False)
    run(["ufw", "allow", "22/tcp"], check=False)
    run(["ufw", "allow", "80/tcp"])
    run(["ufw", "allow", "443/tcp"])

    if ask_yes_no("Enable UFW firewall now?", default=False):
        run(["ufw", "--force", "enable"])
        success("UFW enabled.")
    else:
        warn("UFW installed but not enabled.")

    run(["ufw", "status"], check=False)


def configure_ssl(domain: str, include_www: bool, email: str) -> None:
    section("🔒 HTTPS SSL SETUP")

    if not ask_yes_no("Generate/renew SSL certificate with Certbot?", default=True):
        warn("SSL setup skipped.")
        return

    if not command_exists("certbot"):
        info("Installing Certbot and the Nginx plugin...")
        install_apt(["certbot", "python3-certbot-nginx"])

    domains = [domain]
    if include_www:
        domains.append(f"www.{domain}")

    command = ["certbot", "--nginx"]
    for item in domains:
        command += ["-d", item]
    command += [
        "--non-interactive",
        "--agree-tos",
        "-m",
        email,
        "--redirect",
    ]
    run(command)
    run(["certbot", "renew", "--dry-run"])
    success("SSL setup completed.")


def install_or_repair_nginx_bare() -> None:
    if Path("/etc/nginx/nginx.conf").exists():
        return

    warn("Nginx installation appears corrupted: /etc/nginx/nginx.conf is missing.")
    if not ask_yes_no("Purge and reinstall nginx automatically?", default=False):
        fail("Nginx configuration is missing.")

    info("Purging nginx...")
    run(["apt-get", "remove", "nginx", "nginx-common", "-y"], check=False)
    run(["apt-get", "purge", "nginx", "nginx-common", "-y"], check=False)
    run(["apt-get", "autoremove", "-y"], check=False)

    info("Reinstalling nginx...")
    install_apt(["nginx"])


def activate_nginx_site(config_path: Path, service_name: str, remove_default: bool = False) -> None:
    enabled = Path("/etc/nginx/sites-enabled") / service_name
    enabled.parent.mkdir(parents=True, exist_ok=True)
    if enabled.exists() or enabled.is_symlink():
        enabled.unlink()
    enabled.symlink_to(config_path)

    if remove_default:
        default = Path("/etc/nginx/sites-enabled/default")
        if default.exists() or default.is_symlink():
            default.unlink()


# ==========================================================
# Docker deployment
# ==========================================================

def ensure_docker() -> None:
    section("🐳 DOCKER SETUP")

    if not command_exists("docker"):
        if not ask_yes_no("Docker is not installed. Install Docker now?", default=True):
            fail("Docker is required for TNIX Docker deployment.")

        install_apt(["docker.io"])

    run(["systemctl", "enable", "--now", "docker"])

    if not run(["docker", "compose", "version"], check=False).returncode == 0:
        # Docker package repositories vary. Try the OS package first.
        info("Docker Compose plugin not detected. Installing docker-compose-plugin...")
        result = run(["apt-get", "update", "-y"], check=False)
        if result.returncode == 0:
            run(["apt-get", "install", "-y", "docker-compose-plugin"], check=False)

    if not run(["docker", "compose", "version"], check=False).returncode == 0:
        fail(
            "Docker Compose v2 is required. Docker Compose was not found. "
            "Install Docker Compose v2 and rerun TNIX."
        )

    success(output(["docker", "--version"]))
    success(output(["docker", "compose", "version"]))


def wait_for_container_health(container_name: str, enabled: bool) -> None:
    if not enabled:
        return

    info("Waiting for container health check...")
    for _ in range(20):
        result = run(
            [
                "docker",
                "inspect",
                "-f",
                "{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}",
                container_name,
            ],
            check=False,
            capture=True,
        )
        status = (result.stdout or "").strip()

        if status == "healthy":
            success("Container health check passed.")
            return
        if status == "unhealthy":
            warn("Container health check reported unhealthy.")
            run(["docker", "logs", "--tail", "50", container_name], check=False)
            fail("Container failed health check.")
        if status == "no-healthcheck":
            warn("No Docker health status available.")
            return

        time.sleep(2)

    warn("Container health check did not reach healthy state within the timeout.")
    run(["docker", "logs", "--tail", "50", container_name], check=False)
    fail("Docker container health check timed out.")


def deploy_docker() -> None:
    clear_screen()
    banner()
    require_root()

    section("📋 APPLICATION CONFIGURATION")
    domain = ask("Enter domain name (example.com)")
    if not validate_domain(domain):
        fail("Invalid domain name.")

    project_dir = ensure_absolute_project_dir(ask("Enter project root path"))

    app_module = ask("Enter Flask app module (example: app:app)")
    if not app_module:
        fail("Flask app module is required.")

    service_input = ask("Enter service name", DEFAULT_SERVICE_NAME)
    service_name = sanitize_service_name(service_input)

    port = validate_port(ask("Enter container/app port", str(DEFAULT_APP_PORT)))

    image_name = ask("Enter image name", compose_project_name(service_name))
    image_name = sanitize_image_name(image_name)

    image_tag = ask("Enter image tag", "latest")

    build_local = ask_yes_no("Build Docker image locally from this project?", default=True)

    health_path = ask("Enter health-check path (use 'none' to disable)", DEFAULT_HEALTH_PATH)
    health_enabled = health_path.lower() not in {"none", "/none"}
    if health_enabled and not health_path.startswith("/"):
        health_path = f"/{health_path}"
    if not health_enabled:
        health_path = None

    ssl_email = ask("Enter SSL email")
    if not ssl_email:
        fail("SSL email is required.")

    include_www = ask_yes_no(f"Include www.{domain} in SSL certificate?", default=False)

    deploy_dir = project_dir
    compose_file = deploy_dir / "docker-compose.yml"
    dockerfile = deploy_dir / "Dockerfile"
    dockerignore = deploy_dir / ".dockerignore"
    env_file = deploy_dir / ".env"

    nginx_conf = Path("/etc/nginx/sites-available") / service_name
    systemd_service = Path("/etc/systemd/system") / f"{service_name}.service"
    container_name = sanitize_service_name(service_name)
    compose_project = compose_project_name(service_name)

    server_names = f"{domain} www.{domain}" if include_www else domain

    section("🔎 VALIDATING PROJECT")
    if not (project_dir / "requirements.txt").is_file():
        fail(f"requirements.txt not found in {project_dir}")

    if build_local and not dockerfile.exists():
        info("Dockerfile not found. TNIX will generate one.")
    elif build_local:
        info(f"Existing Dockerfile detected. TNIX will use it: {dockerfile}")

    prepare_system()
    ensure_nginx()
    ensure_docker()

    section("🔐 APPLICATION ENVIRONMENT")
    if env_file.exists():
        success(f"Existing .env found: {env_file}")
        env_file.chmod(0o600)
    else:
        env_file.touch(mode=0o600)
        warn(f"Created empty environment file: {env_file}")
        info("Add application secrets before starting the application.")

    section("📦 DOCKER IMAGE CONFIGURATION")
    if build_local and not dockerfile.exists():
        generate_dockerfile(
            app_port=port,
            app_module=app_module,
            output_path=dockerfile,
            project_dir=project_dir,
        )
        success(f"Dockerfile created: {dockerfile}")

    if build_local and not dockerignore.exists():
        generate_dockerignore(dockerignore)
        success(f".dockerignore created: {dockerignore}")

    section("🧩 GENERATING DOCKER COMPOSE")
    generate_compose(
        image_name=image_name,
        image_tag=image_tag,
        container_name=container_name,
        app_port=port,
        build_local=build_local,
        health_path=health_path,
        output_path=compose_file,
    )
    success(f"Compose file created: {compose_file}")

    info(f"Compose project: [{compose_project}]")
    run(["docker", "compose", "-p", compose_project, "-f", str(compose_file), "config"], cwd=deploy_dir)
    success("Docker Compose configuration is valid.")

    section("🏗️ PREPARING DOCKER IMAGE")
    if build_local:
        info(f"Building {image_name}:{image_tag} ...")
        run(["docker", "compose", "-p", compose_project, "-f", str(compose_file), "build", "--pull"], cwd=deploy_dir)
        success("Docker image built successfully.")
    else:
        info(f"Pulling {image_name}:{image_tag} ...")
        run(["docker", "pull", f"{image_name}:{image_tag}"])
        success("Docker image pulled successfully.")

    section("⚙️ CREATING SYSTEMD SERVICE")
    generate_docker_systemd(
        service_name=service_name,
        compose_project=compose_project,
        compose_file=compose_file,
        deploy_dir=deploy_dir,
        output_path=systemd_service,
    )

    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", service_name])

    section("🚀 STARTING DOCKER APPLICATION")
    run(["systemctl", "restart", service_name])
    time.sleep(3)

    if output(["systemctl", "is-active", service_name], cwd=None) == "active":
        success(f"Systemd service {service_name} is active.")
    else:
        print(f"❌ {service_name} service failed.")
        run(["systemctl", "status", service_name, "--no-pager"], check=False)
        run(["journalctl", "-u", service_name, "--no-pager", "-n", "50"], check=False)
        fail("Docker systemd service failed.")

    section("🧪 CHECKING CONTAINER")
    ps_result = run(
        ["docker", "ps", "--format", "{{.Names}}"],
        capture=True,
    )
    names = set((ps_result.stdout or "").splitlines())
    if container_name not in names:
        print(f"❌ Container {container_name} is not running.")
        run(["docker", "ps", "-a", "--filter", f"name=^{container_name}$"], check=False)
        run(["docker", "logs", container_name, "--tail", "50"], check=False)
        fail("Docker container did not start.")
    success(f"Container {container_name} is running.")
    wait_for_container_health(container_name, health_enabled)

    section("🌐 CREATING NGINX CONFIGURATION")
    generate_docker_nginx(
        domain_names=server_names,
        app_port=port,
        output_path=nginx_conf,
    )
    activate_nginx_site(nginx_conf, service_name, remove_default=False)

    section("🧪 TESTING NGINX CONFIGURATION")
    if run(["nginx", "-t"], check=False).returncode != 0:
        fail("Nginx configuration failed.")
    success("Nginx configuration successful.")

    run(["systemctl", "enable", "nginx"])
    run(["systemctl", "reload", "nginx"])
    success("Nginx reloaded successfully.")

    configure_firewall()
    configure_ssl(domain, include_www, ssl_email)

    section("🔍 FINAL VERIFICATION")
    run(["systemctl", "--no-pager", "--full", "status", service_name], check=False)
    print("")
    run(["docker", "ps", "--filter", f"name=^{container_name}$"], check=False)
    print("")
    run(["ss", "-tulpn"], check=False)

    section("🎉 TNIX V2 DOCKER DEPLOYMENT COMPLETE")
    print("")
    print(f"🌍 Domain:            https://{domain}")
    print(f"📂 Project:           {project_dir}")
    print(f"⚙️ Service:           {service_name}")
    print(f"🐳 Container:         {container_name}")
    print(f"🖼️ Image:             {image_name}:{image_tag}")
    print(f"🔌 Internal port:     127.0.0.1:{port}")
    print(f"📄 Compose:           {compose_file}")
    print(f"🔐 Environment:       {env_file}")
    print(f"🧾 Systemd unit:      {systemd_service}")
    print(f"🌐 Nginx config:      {nginx_conf}")

    section("📋 MANAGEMENT COMMANDS")
    print(f"\nService status:\n  systemctl status {service_name}")
    print(f"\nRestart application:\n  systemctl restart {service_name}")
    print(f"\nStop application:\n  systemctl stop {service_name}")
    print(f"\nApplication logs:\n  docker logs -f {container_name}")
    print("\nDocker status:\n  docker ps")
    print(
        f"\nCompose status:\n  docker compose -p {compose_project} -f {compose_file} ps"
    )
    print(
        f"\nPull latest image and restart:\n  docker compose -p {compose_project} -f {compose_file} pull\n"
        f"  systemctl restart {service_name}"
    )
    print(
        f"\nRebuild local image and restart:\n  docker compose -p {compose_project} -f {compose_file} build --pull\n"
        f"  systemctl restart {service_name}"
    )
    print("\nNginx config test:\n  nginx -t")
    print("\nRestart Nginx:\n  systemctl reload nginx")
    print("\nOpen ports:\n  ss -tulpn")
    print("\nFirewall rules:\n  ufw status")
    print("\n🚀 TNIX v2 deployment completed successfully!\n")


# ==========================================================
# Bare metal deployment
# ==========================================================

def deploy_bare_metal() -> None:
    clear_screen()
    banner()
    require_root()

    section("📋 APPLICATION CONFIGURATION")
    domain = ask("Enter domain name")
    if not validate_domain(domain):
        fail("Invalid domain name.")

    project_dir = ensure_absolute_project_dir(ask("Enter project root path"))

    app_module = ask("Enter Flask app module (example app:app)")
    if not app_module:
        fail("Flask app module is required.")

    service_name = sanitize_service_name(ask("Enter service name", DEFAULT_SERVICE_NAME))
    static_path = Path(ask("Enter static folder path", str(project_dir / "static"))).expanduser().resolve()

    section("🐍 PYTHON VIRTUAL ENVIRONMENT")
    has_venv = ask_yes_no("Do you already have a virtual environment?", default=False)
    if has_venv:
        venv_path = Path(ask("Enter virtual environment path")).expanduser().resolve()
    else:
        venv_path = Path(ask("Enter path to create virtual environment")).expanduser().resolve()
        info("Creating virtual environment...")
        run(["python3", "-m", "venv", str(venv_path)])

        activate_script = venv_path / "bin" / "activate"
        if not activate_script.exists():
            fail(f"Virtual environment was not created correctly: {venv_path}")

        if ask_yes_no("Install requirements.txt packages?", default=True):
            requirements = project_dir / "requirements.txt"
            if requirements.is_file():
                run([str(venv_path / "bin" / "python"), "-m", "pip", "install", "-r", str(requirements)])
            else:
                warn("requirements.txt not found.")

    socket_file = Path("/run") / f"{service_name}.sock"
    nginx_conf = Path("/etc/nginx/sites-available") / service_name
    systemd_service = Path("/etc/systemd/system") / f"{service_name}.service"

    prepare_system()

    if ask_yes_no("Install nginx?", default=True):
        if not command_exists("nginx"):
            install_apt(["nginx"])
    if not command_exists("nginx"):
        fail("Nginx is required.")

    if ask_yes_no("Install certbot + nginx plugin?", default=True):
        if not command_exists("certbot"):
            install_apt(["certbot", "python3-certbot-nginx"])

    install_or_repair_nginx_bare()

    section("📁 SETTING PERMISSIONS")
    run(["chmod", "-R", "755", str(project_dir)], check=False)

    section("⚙️ CREATING SYSTEMD SERVICE")
    generate_bare_systemd(
        service_name=service_name,
        project_dir=project_dir,
        venv_path=venv_path,
        socket_file=socket_file,
        app_module=app_module,
        output_path=systemd_service,
    )

    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", service_name])
    run(["systemctl", "restart", service_name])

    section("🧪 CHECKING GUNICORN SERVICE")
    if run(["systemctl", "is-active", "--quiet", service_name], check=False).returncode == 0:
        success(f"{service_name} service is running.")
    else:
        print(f"❌ {service_name} service failed.")
        run(["journalctl", "-u", service_name, "--no-pager", "-n", "30"], check=False)
        fail("Gunicorn service failed.")

    section("🌐 CREATING NGINX CONFIG")
    generate_bare_nginx(
        domain_names=f"{domain} www.{domain}",
        static_path=static_path,
        socket_file=socket_file,
        output_path=nginx_conf,
    )
    activate_nginx_site(nginx_conf, service_name, remove_default=True)

    section("🧪 TESTING NGINX CONFIGURATION")
    result = run(["nginx", "-t"], check=False, capture=True)
    if result.returncode != 0:
        print(result.stdout or "")
        print(result.stderr or "")
        if not Path("/etc/nginx/nginx.conf").exists():
            fail("Nginx nginx.conf is missing.")
        fail("Unknown Nginx configuration error.")
    success("Nginx configuration successful.")

    # Preserve the original bare-metal workflow of checking for port 80.
    section("🚫 CHECKING PORT 80 CONFLICTS")
    port_result = run(["lsof", "-i", ":80", "-t"], check=False, capture=True)
    pids = [line.strip() for line in (port_result.stdout or "").splitlines() if line.strip()]
    if pids:
        pid = pids[0]
        process_name = output(["ps", "-p", pid, "-o", "comm="]) or "unknown"
        print(f"\n⚠️ Port 80 is currently being used by:\n➡️ {process_name} (PID: {pid})")
        if ask_yes_no("Stop this service/process automatically?", default=False):
            info("Stopping process using port 80...")
            run(["kill", "-9", pid], check=False)
            time.sleep(2)
            success("Port 80 cleaned.")
        else:
            warn("Port cleanup skipped.")
    else:
        print("\n✅ Port 80 is free.")

    section("🚀 STARTING NGINX")
    run(["systemctl", "restart", "nginx"])
    run(["systemctl", "enable", "nginx"])

    section("🔍 VERIFYING NGINX")
    if run(["systemctl", "is-active", "--quiet", "nginx"], check=False).returncode == 0:
        success("Nginx is running successfully.")
    else:
        print("❌ Nginx failed to start.")
        run(["systemctl", "status", "nginx", "--no-pager"], check=False)
        run(["journalctl", "-xeu", "nginx.service", "--no-pager", "-n", "30"], check=False)
        fail("Nginx failed to start.")

    configure_firewall()

    section("🔒 HTTPS SSL SETUP")
    run_certbot = ask_yes_no("Generate SSL certificate with Certbot?", default=True)
    if run_certbot:
        ssl_email = ask("Enter email for SSL notifications")
        if not ssl_email:
            fail("SSL email is required.")
        info("Generating SSL certificate...")
        run([
            "certbot", "--nginx",
            "-d", domain,
            "-d", f"www.{domain}",
            "--non-interactive",
            "--agree-tos",
            "-m", ssl_email,
            "--redirect",
        ])
        info("Testing SSL auto renewal...")
        run(["certbot", "renew", "--dry-run"])
        success("SSL setup completed.")
    else:
        warn("SSL setup skipped.")

    section("🎉 DEPLOYMENT COMPLETE")
    print("")
    print(f"🌍 Domain: https://{domain}")
    print(f"📂 Project: {project_dir}")
    print(f"⚙️ Service: {service_name}")
    print(f"🐍 Virtual Environment: {venv_path}")
    print("")
    section("📋 USEFUL COMMANDS")
    print(f"\nRestart Flask App:\nsystemctl restart {service_name}")
    print(f"\nView Flask Logs:\njournalctl -u {service_name} -f")
    print("\nRestart Nginx:\nsystemctl restart nginx")
    print("\nTest Nginx Config:\nnginx -t")
    print("\nCheck Open Ports:\nss -tulpn")
    print("\n🔥 Firewall Rules:\nufw status")
    print("\n🚀 TNIX deployment completed successfully!\n")


# ==========================================================
# Main
# ==========================================================

def main() -> int:
    deployment_type = choose_deployment_type()
    if deployment_type == 1:
        deploy_docker()
    else:
        deploy_bare_metal()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\n⚠️ TNIX interrupted by user.", file=sys.stderr)
        raise SystemExit(130)
    except subprocess.CalledProcessError as exc:
        cmd = " ".join(shlex.quote(str(x)) for x in exc.cmd)
        print(f"❌ TNIX command failed (exit {exc.returncode}): {cmd}", file=sys.stderr)
        raise SystemExit(exc.returncode)
