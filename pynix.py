#!/usr/bin/env python3
"""
TNIX v2 Docker Compose Generator

Generates a clean, deterministic docker-compose.yml for a Flask application.
The generator intentionally builds YAML line-by-line with Python formatting
instead of composing nested shell heredocs.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def sanitize_compose_project(value: str) -> str:
    """Return a valid Docker Compose project name."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9_-]+", "-", value)
    value = re.sub(r"[-_]+", "-", value)
    value = value.strip("-_")

    if not value:
        value = "tnixapp"

    if not re.match(r"^[a-z0-9]", value):
        value = f"tnix-{value}"

    return value


def yaml_quote(value: str) -> str:
    """Quote a string safely for YAML double-quoted scalar usage."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_compose(
    *,
    image_name: str,
    image_tag: str,
    container_name: str,
    app_port: int,
    env_file: str,
    build_local: bool,
    health_path: str | None,
) -> str:
    """
    Build docker-compose.yml using explicit indentation.

    This avoids shell variable interpolation and heredoc indentation issues.
    """
    image = f"{image_name}:{image_tag}"

    lines: list[str] = [
        "services:",
        "  app:",
        f"    image: {yaml_quote(image)}",
    ]

    if build_local:
        lines.extend(
            [
                "    build:",
                "      context: .",
                "      dockerfile: Dockerfile",
            ]
        )

    lines.extend(
        [
            f"    container_name: {yaml_quote(container_name)}",
            "    restart: unless-stopped",
            "    env_file:",
            f"      - {env_file}",
            "    ports:",
            f'      - "127.0.0.1:{app_port}:{app_port}"',
            "    init: true",
        ]
    )

    if health_path:
        health_path = health_path if health_path.startswith("/") else f"/{health_path}"
        health_url = f"http://127.0.0.1:{app_port}{health_path}"

        health_python = (
            "import urllib.request; "
            f"urllib.request.urlopen({health_url!r}, timeout=5)"
        )

        lines.extend(
            [
                "    healthcheck:",
                "      test:",
                "        - CMD",
                "        - python",
                "        - -c",
                f"        - {yaml_quote(health_python)}",
                "      interval: 30s",
                "      timeout: 5s",
                "      retries: 3",
                "      start_period: 20s",
            ]
        )

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a clean Docker Compose file for TNIX."
    )
    parser.add_argument("--project-dir", required=True, help="Application directory")
    parser.add_argument("--service-name", required=True, help="TNIX service/container name")
    parser.add_argument("--image-name", help="Docker image name; defaults to sanitized service name")
    parser.add_argument("--image-tag", default="latest", help="Docker image tag")
    parser.add_argument("--port", type=int, default=8000, help="Application port")
    parser.add_argument("--env-file", default=".env", help="Compose env_file path")
    parser.add_argument(
        "--build-local",
        action="store_true",
        help="Include a local Docker build section",
    )
    parser.add_argument(
        "--health-path",
        default="/health",
        help="Health endpoint, or 'none' to disable",
    )

    args = parser.parse_args()

    project_dir = Path(args.project_dir).expanduser().resolve()

    if not project_dir.is_dir():
        print(f"ERROR: project directory does not exist: {project_dir}", file=sys.stderr)
        return 1

    if not 1024 <= args.port <= 65535:
        print("ERROR: port must be between 1024 and 65535", file=sys.stderr)
        return 1

    container_name = sanitize_compose_project(args.service_name)
    image_name = args.image_name or container_name
    image_name = sanitize_compose_project(image_name)

    health_path = None if args.health_path.lower() in {"none", "/none"} else args.health_path

    compose_text = build_compose(
        image_name=image_name,
        image_tag=args.image_tag,
        container_name=container_name,
        app_port=args.port,
        env_file=args.env_file,
        build_local=args.build_local,
        health_path=health_path,
    )

    output = project_dir / "docker-compose.yml"
    output.write_text(compose_text, encoding="utf-8")

    print("✅ Docker Compose file generated successfully.")
    print(f"📄 File: {output}")
    print()
    print(compose_text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
