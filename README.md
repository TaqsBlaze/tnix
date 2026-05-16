# TNIX

Automated Flask VPS deployment toolkit for production ready Python applications.

TNIX simplifies the entire deployment process by automatically configuring:

* Gunicorn
* Nginx
* HTTPS/SSL with Certbot
* Systemd services
* Auto start on reboot
* Static file routing
* Reverse proxy configuration
* Production ready Flask deployment

Designed for developers who want to deploy Flask applications to any Linux VPS in minutes instead of manually configuring servers.

---

## Features

* ⚡ One command Flask deployment
* 🔒 Automatic HTTPS SSL setup
* 🌐 Nginx reverse proxy configuration
* 🐍 Gunicorn application server setup
* 🔄 Auto start services with systemd
* 🧹 Automatic nginx repair/reinstall handling
* 🚫 Automatic port conflict cleanup
* 📦 Supports existing or new Python virtual environments
* 🛠 Interactive deployment wizard
* 🚀 VPS ready production configuration

---

## Tech Stack

* Bash
* Flask
* Gunicorn
* Nginx
* Certbot
* Systemd
* Linux VPS

---

## Use Cases

TNIX is ideal for:

* Flask applications
* SaaS deployments
* Startup MVP hosting
* Internal business tools
* API servers
* Portfolio projects
* Production VPS deployments

---

## Example Workflow

```bash
chmod +x tnix.sh
sudo ./tnix.sh
```

TNIX will:

1. Configure your Flask app
2. Create a systemd service
3. Configure nginx
4. Resolve common nginx issues
5. Configure reverse proxy routing
6. Setup HTTPS SSL
7. Enable auto start services
8. Launch your application

---

## Why TNIX?

Deploying Flask apps manually can be repetitive and error prone.

TNIX automates the boring infrastructure setup so developers can focus on building products instead of debugging server configurations.

---

## Target Platforms

Compatible with most Ubuntu/Debian based VPS providers:

* DigitalOcean
* Hetzner
* AWS EC2
* Azure VPS
* Linode
* Vultr
* Oracle Cloud
* Contabo
* Self hosted Linux servers

---

## Roadmap

* Docker deployment support
* Django deployment support
* Node.js deployment support
* Domain verification checks
* Multi app hosting
* Monitoring integration
* Backup automation
* CI/CD integration

---

## License

MIT License

Built for developers who ship fast. 🚀
