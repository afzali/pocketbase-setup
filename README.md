# PocketBase Installer

A comprehensive suite of bash scripts for automating the installation, management, and uninstallation of PocketBase on an Ubuntu server with security hardening, rate limiting, and performance optimization options.

## Features

- **Automated Installation**: Downloads and installs the latest version of PocketBase based on server architecture
- **Admin Account Creation**: Automatically creates the first admin account during installation
- **Nginx Configuration**: Sets up Nginx as a reverse proxy with HTTP/2 support
- **HTTPS Support**: Optional Let's Encrypt SSL certificate configuration
- **Security Hardening**:
  - Security headers (X-Frame-Options, X-Content-Type-Options, etc.)
  - Rate limiting protection against brute-force attacks
  - Suspicious User-Agent blocking
  - fail2ban integration for blocking malicious IPs
- **System Service**: Creates a systemd service for automatic startup and management
- **Backup System**: Configures daily backups with rotation
- **Firewall Configuration**: Sets up UFW firewall with appropriate rules
- **Management Tools**: Includes scripts for managing, monitoring, and troubleshooting your PocketBase installation
- **Clean Uninstallation**: Provides a script to completely remove PocketBase from your system
- **User-Friendly**: Colorful, informative output and comprehensive error handling

## Requirements

- Ubuntu server (18.04 LTS or newer)
- Root or sudo access
- A domain name pointing to your server

## Script Overview

This package includes the following scripts:

1. **install_pocketbase.sh**: Main installation script
2. **uninstall_pocketbase.sh**: Complete removal of PocketBase and its configurations
3. **pocketbase_manager.sh**: Management utility for controlling and monitoring PocketBase
4. **check_admin_setup.sh**: Helper script to find or regenerate admin setup URLs

## Installation

1. Copy the scripts to your Ubuntu server
2. Make them executable:
   ```
   chmod +x *.sh
   ```
3. Run the installation script as root or with sudo:
   ```
   sudo ./install_pocketbase.sh
   ```
4. Follow the interactive prompts to configure your PocketBase installation

## Configuration Options

The installation script will prompt you for the following configuration options:

- **Domain Name**: The domain name for your PocketBase instance
- **Subdomain**: Optional subdomain for your PocketBase instance
- **PocketBase Port**: The port PocketBase will listen on (default: 8090)
- **HTTPS**: Whether to enable HTTPS using Let's Encrypt
- **Rate Limiting**: Configure rate limiting to protect against brute-force attacks
- **Security Settings**: Additional security hardening options
- **Suspicious User-Agent Blocking**: Block requests with suspicious User-Agents
- **Admin Account**: Email and password for the first admin account

## Management

After installation, you can use the management script to control your PocketBase instance:

```
sudo ./pocketbase_manager.sh
```

The management script provides the following options:

- View service status
- Start/stop/restart the PocketBase service
- Enable/disable the service at boot
- View and follow logs
- Clear all logs
- Check accessibility
- View Nginx configuration
- Run PocketBase binary directly (for debugging)
- Stop/restart directly running PocketBase binary

You can also use command-line arguments:

```
sudo ./pocketbase_manager.sh status
sudo ./pocketbase_manager.sh restart
sudo ./pocketbase_manager.sh logs 100
sudo ./pocketbase_manager.sh clear-logs
sudo ./pocketbase_manager.sh run-binary
```

## Uninstallation

If you need to remove PocketBase from your system, use the uninstallation script:

```
sudo ./uninstall_pocketbase.sh
```

The script will:
- Stop and remove the PocketBase service
- Remove Nginx configurations
- Remove fail2ban rules
- Remove backup cron jobs
- Remove PocketBase files and directories
- Remove the PocketBase user
- Update firewall rules
- Clear all logs

You'll have the option to keep your data directory for backup purposes.

## Post-Installation

After installation, you'll need to:

1. Update your DNS records to point your domain to your server's IP address
2. Access the PocketBase Admin UI at `https://yourdomain.com/_/` using the admin credentials you provided during installation
3. Regularly check and update your system and packages

## Backup System

The script configures a daily backup system that:

- Creates backups at 2 AM every day
- Stores backups in `/opt/pocketbase/backups`
- Automatically removes backups older than 7 days

## Security Considerations

This script implements several security best practices:

- Runs PocketBase as a dedicated non-root user
- Configures security headers in Nginx
- Sets up fail2ban to block malicious IPs
- Configures a firewall with restrictive rules
- Enables HTTPS with proper security headers
- Provides secure admin account creation

## Troubleshooting

If you encounter issues with your PocketBase installation:

1. Check the service status: `sudo ./pocketbase_manager.sh status`
2. View the logs: `sudo ./pocketbase_manager.sh logs`
3. Try running PocketBase directly to see console output: `sudo ./pocketbase_manager.sh run-binary`
4. Restart the service: `sudo ./pocketbase_manager.sh restart`

## License

This script is provided under the MIT License. Feel free to modify and distribute it as needed.
