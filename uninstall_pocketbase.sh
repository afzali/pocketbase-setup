#!/bin/bash

# ========================================================================
# PocketBase Uninstallation Script
# ========================================================================
# This script removes PocketBase, its configuration, and related components
# from an Ubuntu server. Use with caution as it will delete all PocketBase
# data and configuration.
# ========================================================================

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display messages with color
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display section headers
print_section() {
    local message=$1
    echo -e "\n${PURPLE}==== $message =====${NC}"
}

# Function to display error messages and exit
print_error_and_exit() {
    local message=$1
    local exit_code=$2
    echo -e "${RED}ERROR: $message${NC}"
    exit $exit_code
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error_and_exit "Please run this script as root or with sudo" 1
fi

# Display warning and confirmation
clear
print_message "$RED" "
╔═══════════════════════════════════════════════════╗
║                                                   ║
║       PocketBase Uninstallation                   ║
║                                                   ║
╚═══════════════════════════════════════════════════╝"

print_message "$RED" "WARNING: This script will completely remove PocketBase and all its data."
print_message "$RED" "This action CANNOT be undone and all your data will be lost!"
print_message "$YELLOW" "Are you absolutely sure you want to proceed? (yes/no)"
read -r CONFIRM

# Convert to lowercase and check for variations of yes
CONFIRM_LC=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
if [[ "$CONFIRM_LC" != "yes" && "$CONFIRM_LC" != "y" ]]; then
    print_message "$BLUE" "Uninstallation cancelled."
    exit 0
fi

print_message "$YELLOW" "Do you want to keep your data directory for backup purposes? (yes/no)"
read -r KEEP_DATA
KEEP_DATA_LC=$(echo "$KEEP_DATA" | tr '[:upper:]' '[:lower:]')
if [[ "$KEEP_DATA_LC" == "yes" || "$KEEP_DATA_LC" == "y" ]]; then
    KEEP_DATA="yes"
else
    KEEP_DATA="no"
fi

# Start uninstallation
print_section "Starting Uninstallation"

# Stop and disable PocketBase service
print_section "Removing PocketBase Service"
print_message "$BLUE" "Stopping PocketBase service..."
systemctl stop pocketbase 2>/dev/null

print_message "$BLUE" "Disabling PocketBase service..."
systemctl disable pocketbase 2>/dev/null

print_message "$BLUE" "Removing service file..."
rm -f /etc/systemd/system/pocketbase.service

print_message "$BLUE" "Reloading systemd daemon..."
systemctl daemon-reload

# Remove Nginx configuration
print_section "Removing Nginx Configuration"
print_message "$BLUE" "Finding Nginx configuration files for PocketBase..."
NGINX_CONFIGS=$(find /etc/nginx/sites-available -type f -exec grep -l "proxy_pass.*pocketbase\|proxy_pass.*:8090" {} \; 2>/dev/null)

if [ -n "$NGINX_CONFIGS" ]; then
    for config in $NGINX_CONFIGS; do
        print_message "$BLUE" "Removing Nginx configuration: $config"
        
        # Get the domain name from the config file
        DOMAIN=$(grep -oP "server_name\s+\K[^;]+" "$config" 2>/dev/null | tr -d ' ')
        
        # Remove symbolic link if it exists
        if [ -n "$DOMAIN" ]; then
            rm -f "/etc/nginx/sites-enabled/$DOMAIN" 2>/dev/null
        fi
        
        # Remove the actual config file
        rm -f "$config"
    done
    
    # Remove any other symbolic links that might point to PocketBase configs
    find /etc/nginx/sites-enabled -type l -exec grep -l "proxy_pass.*pocketbase\|proxy_pass.*:8090" {} \; 2>/dev/null | xargs -r rm -f
    
    # Restart Nginx
    print_message "$BLUE" "Restarting Nginx..."
    systemctl restart nginx
else
    print_message "$YELLOW" "No Nginx configuration found for PocketBase."
fi

# Remove suspicious agents configuration if it exists
if [ -f "/etc/nginx/conf.d/suspicious_agents.conf" ]; then
    print_message "$BLUE" "Removing suspicious agents configuration..."
    rm -f /etc/nginx/conf.d/suspicious_agents.conf
fi

# Remove rate limiting configuration from nginx.conf if it exists
if grep -q "limit_req_zone.*pocketbase_limit" /etc/nginx/nginx.conf; then
    print_message "$BLUE" "Removing rate limiting configuration from nginx.conf..."
    sed -i '/limit_req_zone.*pocketbase_limit/d' /etc/nginx/nginx.conf
    systemctl restart nginx
fi

# Check for running PocketBase processes and kill them
print_section "Checking for Running PocketBase Processes"
if pgrep -f "/opt/pocketbase/pocketbase" > /dev/null; then
    print_message "$BLUE" "Found running PocketBase processes. Terminating them..."
    pkill -f "/opt/pocketbase/pocketbase"
    sleep 2
    
    # Force kill if still running
    if pgrep -f "/opt/pocketbase/pocketbase" > /dev/null; then
        print_message "$YELLOW" "Some processes did not terminate gracefully. Force killing..."
        pkill -9 -f "/opt/pocketbase/pocketbase"
    fi
    
    print_message "$GREEN" "All PocketBase processes terminated."
else
    print_message "$YELLOW" "No running PocketBase processes found."
fi

# Clear PocketBase logs
print_section "Clearing PocketBase Logs"
print_message "$BLUE" "Clearing systemd journal logs for PocketBase..."
journalctl --vacuum-time=1s --unit=pocketbase 2>/dev/null

# Clear Nginx logs related to PocketBase
print_message "$BLUE" "Clearing Nginx logs related to PocketBase..."
NGINX_LOG_FILES=$(find /var/log/nginx -type f -name "*pocketbase*" 2>/dev/null)
if [ -n "$NGINX_LOG_FILES" ]; then
    for log_file in $NGINX_LOG_FILES; do
        > "$log_file"
        print_message "$CYAN" "Cleared: $log_file"
    done
else
    print_message "$YELLOW" "No PocketBase-specific Nginx logs found."
fi

# Remove fail2ban configuration
print_section "Removing Fail2ban Configuration"
if [ -f "/etc/fail2ban/filter.d/pocketbase.conf" ]; then
    print_message "$BLUE" "Removing Fail2ban filter for PocketBase..."
    rm -f /etc/fail2ban/filter.d/pocketbase.conf
    
    # Remove jail configuration if it exists
    if grep -q "pocketbase" /etc/fail2ban/jail.local 2>/dev/null; then
        print_message "$BLUE" "Removing PocketBase jail from fail2ban..."
        sed -i '/\[pocketbase\]/,/^$/d' /etc/fail2ban/jail.local
        systemctl restart fail2ban
    fi
fi

# Remove backup cron job
print_section "Removing Backup Cron Job"
if crontab -l 2>/dev/null | grep -q "pocketbase"; then
    print_message "$BLUE" "Removing backup cron job..."
    (crontab -l 2>/dev/null | grep -v "pocketbase") | crontab -
fi

# Remove PocketBase files
print_section "Removing PocketBase Files"
if [ "$KEEP_DATA" = "yes" ]; then
    print_message "$BLUE" "Moving data directory to backup location..."
    BACKUP_DIR="/opt/pocketbase_data_backup_$(date +%Y%m%d%H%M%S)"
    mv /opt/pocketbase/pb_data "$BACKUP_DIR" 2>/dev/null
    print_message "$GREEN" "Data backed up to: $BACKUP_DIR"
else
    print_message "$BLUE" "Removing PocketBase data directory..."
    rm -rf /opt/pocketbase/pb_data
fi

print_message "$BLUE" "Removing PocketBase directory..."
rm -rf /opt/pocketbase

# Remove PocketBase user
print_section "Removing PocketBase User"
print_message "$BLUE" "Checking if PocketBase user exists..."
if id "pocketbase" &>/dev/null; then
    print_message "$BLUE" "Removing 'pocketbase' user..."
    userdel -r pocketbase 2>/dev/null
    print_message "$GREEN" "User 'pocketbase' removed."
else
    print_message "$YELLOW" "User 'pocketbase' does not exist."
fi

# Update firewall rules
print_section "Updating Firewall Rules"
print_message "$BLUE" "Checking firewall rules..."
if ufw status | grep -q "8090"; then
    print_message "$BLUE" "Removing PocketBase port from firewall..."
    ufw delete allow 8090/tcp 2>/dev/null
fi

# Uninstallation complete
print_section "Uninstallation Complete"
print_message "$GREEN" "PocketBase has been successfully uninstalled from your system."

if [ "$KEEP_DATA" = "yes" ]; then
    print_message "$YELLOW" "Your PocketBase data has been backed up to: $BACKUP_DIR"
else
    print_message "$RED" "All PocketBase data has been permanently deleted."
fi

print_message "$BLUE" "You can now reinstall PocketBase if needed."

exit 0
