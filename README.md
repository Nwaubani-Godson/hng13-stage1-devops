# HNG13 Stage 1 DevOps - Automated Deployment Script

## Overview

A production-grade Bash script that automates the complete deployment of a Dockerized application on a remote Linux server with Nginx reverse proxy configuration.

## Features

- Full automation from repository clone to production deployment
- Idempotent design (safe to run multiple times)
- Comprehensive logging with timestamps
- Cleanup mode for resource removal
- Automatic Nginx reverse proxy setup

## Prerequisites

**Local Machine:**
- Bash shell
- Git and SSH client
- rsync utility

**Remote Server:**
- Ubuntu/Debian Linux
- SSH access with key-based authentication
- Sudo privileges

## Usage

### Deploy Application

```bash
chmod +x deploy.sh
./deploy.sh
```

You'll be prompted for:
- GitHub Repository URL
- Personal Access Token (PAT)
- Branch name (default: main)
- Remote server username
- Remote server IP address
- SSH private key path
- Application port

### Cleanup Resources

```bash
./deploy.sh --cleanup
```

## What It Does

1. Clones and validates your repository
2. Prepares remote server (installs Docker, Nginx)
3. Transfers project files via rsync
4. Builds and deploys Docker container
5. Configures Nginx reverse proxy on port 80
6. Validates deployment and logs everything

## Configuration

- **Docker Image**: `hng13_stage1_app_image`
- **Container Name**: `hng13_stage1_app_cont`
- **App Directory**: `/home/[user]/hng13_stage1_app`
- **Nginx Config**: `/etc/nginx/sites-available/hng13_stage1_app`
- **Logs**: `deploy_YYYYMMDD_HHMMSS.log`

## Troubleshooting

**SSH Connection Failed**
- Verify SSH key path and permissions: `chmod 600 ~/.ssh/id_ed25519`

**Docker Permission Denied**
- Script adds user to docker group automatically
- May require logout/login for changes to take effect

**Port Already in Use**
- Stop conflicting services or choose a different port

**Container Not Running**
- Check logs: `docker logs hng13_stage1_app_cont`
- Verify Dockerfile configuration

## Access Your Application

After successful deployment:
```
http://[SERVER_IP]
```

Check container status:
```bash
docker ps
```


## Author

Godson Nwaubani - HNG13 DevOps Intern

---

**Note**: This project is part of the HNG13 DevOps Internship Stage 1 Task.