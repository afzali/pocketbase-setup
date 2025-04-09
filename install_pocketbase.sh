#!/bin/bash

# ========================================================================
# PocketBase Installation and Configuration Script
# ========================================================================
# This script automates the installation and configuration of PocketBase
# on an Ubuntu server with security hardening, rate limiting, and
# performance optimization options.
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate domain name
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate port number
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# Function to validate yes/no input
validate_yes_no() {
    local input=$1
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    if [[ "$input" == "y" || "$input" == "yes" || "$input" == "n" || "$input" == "no" ]]; then
        return 0
    fi
    return 1
}

# Function to validate numeric input
validate_numeric() {
    local input=$1
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate rate limit input
validate_rate_limit() {
    local input=$1
    if ! [[ "$input" =~ ^[0-9]+r/s$ ]]; then
        return 1
    fi
    return 0
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error_and_exit "Please run this script as root or with sudo" 1
    fi
}

# Function to update system packages
update_system() {
    print_section "Updating System Packages"
    print_message "$BLUE" "Updating package lists..."
    apt-get update -y || print_error_and_exit "Failed to update package lists" 2
    
    print_message "$BLUE" "Upgrading packages..."
    apt-get upgrade -y || print_error_and_exit "Failed to upgrade packages" 3
    
    print_message "$GREEN" "System packages updated successfully!"
}

# Function to install required dependencies
install_dependencies() {
    print_section "Installing Dependencies"
    print_message "$BLUE" "Installing required packages..."
    apt-get install -y curl unzip nginx ufw || print_error_and_exit "Failed to install dependencies" 4
    
    print_message "$GREEN" "Dependencies installed successfully!"
}

# Function to create PocketBase user
create_pocketbase_user() {
    print_section "Creating PocketBase User"
    
    if id "pocketbase" &>/dev/null; then
        print_message "$YELLOW" "User 'pocketbase' already exists. Skipping user creation."
    else
        print_message "$BLUE" "Creating 'pocketbase' user..."
        useradd -m -s /bin/bash pocketbase || print_error_and_exit "Failed to create 'pocketbase' user" 5
        print_message "$GREEN" "User 'pocketbase' created successfully!"
    fi
}

# Function to download and install PocketBase
install_pocketbase() {
    print_section "Installing PocketBase"
    
    # Determine system architecture
    local arch
    arch=$(uname -m)
    local pb_arch
    
    case $arch in
        x86_64)
            pb_arch="linux_amd64"
            ;;
        aarch64|arm64)
            pb_arch="linux_arm64"
            ;;
        *)
            print_error_and_exit "Unsupported architecture: $arch" 6
            ;;
    esac
    
    # Get latest PocketBase version
    print_message "$BLUE" "Determining latest PocketBase version..."
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/pocketbase/pocketbase/releases/latest | grep -Po '"tag_name": "\K.*?(?=")') || print_error_and_exit "Failed to determine latest PocketBase version" 7
    
    if [ -z "$latest_version" ]; then
        print_error_and_exit "Failed to determine latest PocketBase version" 7
    fi
    
    # Remove 'v' prefix if present in the version string
    latest_version=${latest_version#v}
    
    print_message "$BLUE" "Latest PocketBase version: $latest_version"
    
    # Create PocketBase directory
    print_message "$BLUE" "Creating PocketBase directory..."
    mkdir -p /opt/pocketbase || print_error_and_exit "Failed to create PocketBase directory" 8
    
    # Download PocketBase
    print_message "$BLUE" "Downloading PocketBase..."
    local download_url="https://github.com/pocketbase/pocketbase/releases/download/v${latest_version}/pocketbase_${latest_version}_${pb_arch}.zip"
    print_message "$YELLOW" "Download URL: $download_url"
    
    # Create a temporary directory for downloads
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/pocketbase.zip"
    
    # Download with progress and error checking
    if ! curl -L --progress-bar -o "$zip_file" "$download_url"; then
        rm -rf "$temp_dir"
        print_error_and_exit "Failed to download PocketBase from $download_url" 9
    fi
    
    # Verify the downloaded file is a valid zip file
    if ! command_exists "file"; then
        apt-get install -y file || print_message "$YELLOW" "Warning: 'file' command not available for zip verification"
    fi
    
    if command_exists "file"; then
        file_type=$(file -b "$zip_file")
        if [[ "$file_type" != *"Zip archive"* ]]; then
            print_message "$RED" "Downloaded file is not a valid zip archive: $file_type"
            print_message "$YELLOW" "Attempting alternative download method..."
            
            # Try alternative download with wget if available
            if command_exists "wget"; then
                rm -f "$zip_file"
                if ! wget -q --show-progress -O "$zip_file" "$download_url"; then
                    rm -rf "$temp_dir"
                    print_error_and_exit "Failed to download PocketBase using wget" 9
                fi
            else
                rm -rf "$temp_dir"
                print_error_and_exit "Downloaded file is not a valid zip archive and wget is not available" 9
            fi
        fi
    fi
    
    # Check file size to ensure it's not empty or too small
    local file_size=$(stat -c%s "$zip_file" 2>/dev/null || stat -f%z "$zip_file" 2>/dev/null)
    if [ -z "$file_size" ] || [ "$file_size" -lt 1000 ]; then
        rm -rf "$temp_dir"
        print_error_and_exit "Downloaded file is too small or empty: $file_size bytes" 9
    fi
    
    print_message "$GREEN" "Download completed successfully! File size: $file_size bytes"
    
    # Extract PocketBase
    print_message "$BLUE" "Extracting PocketBase..."
    if ! unzip -o "$zip_file" -d /opt/pocketbase; then
        # If unzip fails, try to get more detailed error information
        unzip -t "$zip_file"
        rm -rf "$temp_dir"
        print_error_and_exit "Failed to extract PocketBase" 10
    fi
    
    # Set permissions
    print_message "$BLUE" "Setting permissions..."
    chown -R pocketbase:pocketbase /opt/pocketbase || print_error_and_exit "Failed to set ownership" 11
    chmod -R 755 /opt/pocketbase || print_error_and_exit "Failed to set permissions" 12
    
    # Clean up
    rm -rf "$temp_dir"
    
    # Verify PocketBase executable exists
    if [ ! -f "/opt/pocketbase/pocketbase" ]; then
        print_error_and_exit "PocketBase executable not found after extraction" 13
    fi
    
    print_message "$GREEN" "PocketBase installed successfully!"
}

# Function to create systemd service
create_systemd_service() {
    print_section "Creating Systemd Service"
    
    local service_file="/etc/systemd/system/pocketbase.service"
    
    print_message "$BLUE" "Creating systemd service file..."
    cat > "$service_file" << EOF
[Unit]
Description=PocketBase service
After=network.target

[Service]
Type=simple
User=pocketbase
Group=pocketbase
WorkingDirectory=/opt/pocketbase
ExecStart=/opt/pocketbase/pocketbase serve --http="0.0.0.0:${POCKETBASE_PORT}"
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    print_message "$BLUE" "Reloading systemd daemon..."
    systemctl daemon-reload || print_error_and_exit "Failed to reload systemd daemon" 13
    
    print_message "$BLUE" "Enabling PocketBase service..."
    systemctl enable pocketbase || print_error_and_exit "Failed to enable PocketBase service" 14
    
    print_message "$BLUE" "Starting PocketBase service..."
    systemctl start pocketbase || print_error_and_exit "Failed to start PocketBase service" 15
    
    print_message "$GREEN" "PocketBase service created and started successfully!"
}

# Function to configure Nginx
configure_nginx() {
    print_section "Configuring Nginx"
    
    local nginx_conf="/etc/nginx/sites-available/$DOMAIN"
    local full_domain="$DOMAIN"
    
    if [ -n "$SUBDOMAIN" ]; then
        full_domain="$SUBDOMAIN.$DOMAIN"
    fi
    
    print_message "$BLUE" "Creating Nginx configuration..."
    
    # Start building the configuration
    cat > "$nginx_conf" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $full_domain;

    location / {
        proxy_pass http://localhost:$POCKETBASE_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;

        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
EOF
    
    # Add rate limiting if enabled
    if [ "$ENABLE_RATE_LIMITING" = "y" ]; then
        print_message "$BLUE" "Adding rate limiting configuration..."
        
        # Add rate limiting zone to http block in nginx.conf
        if ! grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
            sed -i '/http {/a \    limit_req_zone $binary_remote_addr zone=pocketbase_limit:10m rate='"$RATE_LIMIT"';' /etc/nginx/nginx.conf
        fi
        
        # Add rate limiting to location block
        cat >> "$nginx_conf" << EOF
        limit_req zone=pocketbase_limit burst=$RATE_LIMIT_BURST nodelay;
EOF
    fi
    
    # Add security headers if enabled
    if [ "$CONFIGURE_SECURITY" = "y" ]; then
        print_message "$BLUE" "Adding security headers..."
        
        cat >> "$nginx_conf" << EOF
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy "strict-origin-when-cross-origin";
EOF
        
        if [ "$ENABLE_HTTPS" = "y" ]; then
            cat >> "$nginx_conf" << EOF
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";
EOF
        fi
    fi
    
    # Block suspicious User-Agents if enabled
    if [ "$BLOCK_SUSPICIOUS_UAS" = "y" ]; then
        print_message "$BLUE" "Adding suspicious User-Agent blocking..."
        
        # Create map for suspicious User-Agents
        if ! grep -q "map \$http_user_agent \$suspicious_agent" /etc/nginx/nginx.conf; then
            cat > /etc/nginx/conf.d/suspicious_agents.conf << EOF
map \$http_user_agent \$suspicious_agent {
    default 0;
    ~*(curl|wget|python|nikto|sqlmap|nmap|masscan|libwww|perl|go-http|java|ruby|php) 1;
    ~*(nessus|w3af|openvas|metasploit|burpsuite|ZAP|hydra|acunetix) 1;
    "" 1;
}
EOF
        fi
        
        # Add condition to block suspicious agents
        cat >> "$nginx_conf" << EOF
        # Block suspicious User-Agents
        if (\$suspicious_agent = 1) {
            return 403;
        }
EOF
    fi
    
    # Close the location and server blocks
    cat >> "$nginx_conf" << EOF
    }
}
EOF
    
    print_message "$BLUE" "Creating symbolic link..."
    ln -sf "$nginx_conf" /etc/nginx/sites-enabled/ || print_error_and_exit "Failed to create symbolic link" 16
    
    print_message "$BLUE" "Removing default Nginx site..."
    rm -f /etc/nginx/sites-enabled/default
    
    print_message "$BLUE" "Testing Nginx configuration..."
    nginx -t || print_error_and_exit "Nginx configuration test failed" 17
    
    print_message "$BLUE" "Restarting Nginx..."
    systemctl restart nginx || print_error_and_exit "Failed to restart Nginx" 18
    
    print_message "$GREEN" "Nginx configured successfully!"
}

# Function to configure HTTPS with Let's Encrypt
configure_https() {
    print_section "Configuring HTTPS with Let's Encrypt"
    
    local full_domain="$DOMAIN"
    if [ -n "$SUBDOMAIN" ]; then
        full_domain="$SUBDOMAIN.$DOMAIN"
    fi
    
    print_message "$BLUE" "Installing Certbot..."
    apt-get install -y certbot python3-certbot-nginx || print_error_and_exit "Failed to install Certbot" 19
    
    print_message "$BLUE" "Obtaining SSL certificate..."
    certbot --nginx -d "$full_domain" --non-interactive --agree-tos --email "admin@$DOMAIN" || print_error_and_exit "Failed to obtain SSL certificate" 20
    
    print_message "$GREEN" "HTTPS configured successfully!"
}

# Function to configure fail2ban
configure_fail2ban() {
    print_section "Configuring fail2ban"
    
    print_message "$BLUE" "Installing fail2ban..."
    apt-get install -y fail2ban || print_error_and_exit "Failed to install fail2ban" 21
    
    print_message "$BLUE" "Creating PocketBase jail configuration..."
    
    # Create PocketBase jail configuration
    cat > /etc/fail2ban/jail.d/pocketbase.conf << EOF
[pocketbase]
enabled = true
port = http,https
filter = pocketbase
logpath = /var/log/nginx/access.log
maxretry = 5
findtime = 300
bantime = 3600
EOF
    
    # Create PocketBase filter
    cat > /etc/fail2ban/filter.d/pocketbase.conf << EOF
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) .*(admin|_|api).* (401|403|404|429)
ignoreregex =
EOF
    
    print_message "$BLUE" "Restarting fail2ban..."
    systemctl restart fail2ban || print_error_and_exit "Failed to restart fail2ban" 22
    
    print_message "$GREEN" "fail2ban configured successfully!"
}

# Function to configure firewall
configure_firewall() {
    print_section "Configuring Firewall"
    
    print_message "$BLUE" "Setting up UFW firewall..."
    
    # Check if UFW is installed
    if ! command_exists ufw; then
        print_message "$BLUE" "Installing UFW..."
        apt-get install -y ufw || print_error_and_exit "Failed to install UFW" 23
    fi
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        print_message "$BLUE" "Enabling UFW..."
        ufw --force enable || print_error_and_exit "Failed to enable UFW" 24
    fi
    
    # Allow SSH
    print_message "$BLUE" "Allowing SSH connections..."
    ufw allow ssh || print_error_and_exit "Failed to allow SSH connections" 25
    
    # Allow HTTP and HTTPS
    print_message "$BLUE" "Allowing HTTP and HTTPS connections..."
    ufw allow http || print_error_and_exit "Failed to allow HTTP connections" 26
    ufw allow https || print_error_and_exit "Failed to allow HTTPS connections" 27
    
    print_message "$GREEN" "Firewall configured successfully!"
}

# Function to create backup cron job
create_backup_cron() {
    print_section "Creating Backup Cron Job"
    
    print_message "$BLUE" "Creating backup script..."
    
    # Create backup directory
    mkdir -p /opt/pocketbase/backups || print_error_and_exit "Failed to create backup directory" 28
    chown pocketbase:pocketbase /opt/pocketbase/backups || print_error_and_exit "Failed to set ownership for backup directory" 29
    
    # Create backup script
    cat > /opt/pocketbase/backup.sh << 'EOF'
#!/bin/bash

# Backup script for PocketBase

# Set variables
BACKUP_DIR="/opt/pocketbase/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/pocketbase_backup_$DATE.tar.gz"

# Stop PocketBase service
systemctl stop pocketbase

# Create backup
tar -czf "$BACKUP_FILE" -C /opt/pocketbase pb_data

# Start PocketBase service
systemctl start pocketbase

# Remove backups older than 7 days
find "$BACKUP_DIR" -name "pocketbase_backup_*" -type f -mtime +7 -delete
EOF
    
    # Set permissions for backup script
    chmod +x /opt/pocketbase/backup.sh || print_error_and_exit "Failed to set permissions for backup script" 30
    chown pocketbase:pocketbase /opt/pocketbase/backup.sh || print_error_and_exit "Failed to set ownership for backup script" 31
    
    print_message "$BLUE" "Creating cron job..."
    
    # Create cron job to run backup script daily at 2 AM
    echo "0 2 * * * /opt/pocketbase/backup.sh" > /etc/cron.d/pocketbase-backup || print_error_and_exit "Failed to create cron job" 32
    
    print_message "$GREEN" "Backup cron job created successfully!"
}

# Function to display installation summary and admin setup URL
display_summary() {
    print_section "Installation Complete"
    
    print_message "$GREEN" "PocketBase has been successfully installed and configured!"
    
    local full_domain="$DOMAIN"
    if [ -n "$SUBDOMAIN" ]; then
        full_domain="$SUBDOMAIN.$DOMAIN"
    fi
    
    local protocol="http"
    if [ "$ENABLE_HTTPS" = "y" ]; then
        protocol="https"
    fi
    
    print_message "$BLUE" "You can access your PocketBase instance at: $protocol://$full_domain"
    print_message "$BLUE" "Admin UI is available at: $protocol://$full_domain/_/"
    
    # Ask for admin credentials
    print_section "Admin Account Setup"
    print_message "$YELLOW" "Let's create an admin account for PocketBase."
    
    # Get admin email
    while true; do
        print_message "$YELLOW" "Enter admin email address:"
        read -r ADMIN_EMAIL
        
        if [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_message "$RED" "Invalid email format. Please enter a valid email address."
        fi
    done
    
    # Get admin password
    while true; do
        print_message "$YELLOW" "Enter admin password (minimum 8 characters):"
        read -rs ADMIN_PASSWORD
        echo
        
        if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
            print_message "$YELLOW" "Confirm admin password:"
            read -rs ADMIN_PASSWORD_CONFIRM
            echo
            
            if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
                break
            else
                print_message "$RED" "Passwords do not match. Please try again."
            fi
        else
            print_message "$RED" "Password must be at least 8 characters long. Please try again."
        fi
    done
    
    # Create admin account
    print_message "$BLUE" "Creating admin account..."
    
    # Stop PocketBase service temporarily to use the CLI
    systemctl stop pocketbase
    
    # Make sure the data directory has correct permissions
    print_message "$BLUE" "Ensuring correct permissions on data directory..."
    chown -R pocketbase:pocketbase /opt/pocketbase/pb_data
    chmod -R 755 /opt/pocketbase/pb_data
    
    # Create a temporary password file to avoid shell escaping issues
    print_message "$BLUE" "Setting up admin credentials..."
    TEMP_CRED_FILE=$(mktemp)
    echo "$ADMIN_PASSWORD" > "$TEMP_CRED_FILE"
    chown pocketbase:pocketbase "$TEMP_CRED_FILE"
    chmod 600 "$TEMP_CRED_FILE"
    
    # Try to create the admin account using different methods
    ADMIN_CREATED=false
    
    # Method 1: Use superuser upsert with password file
    if su - pocketbase -c "cd /opt/pocketbase && ./pocketbase superuser upsert '$ADMIN_EMAIL' \$(cat $TEMP_CRED_FILE)"; then
        ADMIN_CREATED=true
        print_message "$GREEN" "Admin account created successfully with superuser upsert!"
    # Method 2: Try direct command with simpler password
    elif su - pocketbase -c "cd /opt/pocketbase && ./pocketbase superuser upsert '$ADMIN_EMAIL' '${ADMIN_PASSWORD//\'/\\\'}'"; then
        ADMIN_CREATED=true
        print_message "$GREEN" "Admin account created successfully with direct command!"
    # Method 3: Try with serve command
    elif su - pocketbase -c "cd /opt/pocketbase && ./pocketbase serve --http='0.0.0.0:$POCKETBASE_PORT' --createAdminUser='$ADMIN_EMAIL:${ADMIN_PASSWORD//\'/\\\'}' --automigrate --dev"; then
        ADMIN_CREATED=true
        print_message "$GREEN" "Admin account created successfully with serve command!"
        # Kill the temporary PocketBase process
        pkill -f "pocketbase serve --http='0.0.0.0:$POCKETBASE_PORT' --createAdminUser"
    fi
    
    # Clean up the temporary file
    rm -f "$TEMP_CRED_FILE"
    
    # If all methods failed, provide manual instructions
    if [ "$ADMIN_CREATED" = "false" ]; then
        print_message "$RED" "Failed to create admin account automatically."
        print_message "$YELLOW" "You can create it manually after installation by running:"
        print_message "$CYAN" "1. Stop the service: sudo systemctl stop pocketbase"
        print_message "$CYAN" "2. Create the admin: sudo -u pocketbase /opt/pocketbase/pocketbase superuser upsert your@email.com yourpassword"
        print_message "$CYAN" "3. Start the service: sudo systemctl start pocketbase"
    fi
    
    # Make sure all files have the correct ownership
    print_message "$BLUE" "Setting final permissions..."
    chown -R pocketbase:pocketbase /opt/pocketbase
    
    # Start PocketBase service again
    print_message "$BLUE" "Restarting PocketBase service..."
    systemctl restart pocketbase
    sleep 3  # Give it a moment to start up properly
    
    print_section "Next Steps"
    print_message "$BLUE" "1. Update your DNS records to point your domain to this server's IP address."
    print_message "$BLUE" "2. Access the PocketBase Admin UI at $protocol://$full_domain/_/ and log in with:"
    print_message "$BLUE" "   - Email: $ADMIN_EMAIL"
    print_message "$BLUE" "   - Password: (the password you entered)"
    print_message "$BLUE" "3. Remember to regularly check and update your system and packages."
    
    if [ "$ENABLE_BACKUPS" = "y" ]; then
        print_message "$BLUE" "4. Backups are automatically created daily at $BACKUP_TIME and stored in $BACKUP_DIR."
    fi
}

# Main script execution starts here
clear
print_message "$CYAN" "
╔═══════════════════════════════════════════════════╗
║                                                   ║
║       PocketBase Installation and Setup           ║
║                                                   ║
╚═══════════════════════════════════════════════════╝"

# Check if running as root
check_root

# Prompt for domain name
while true; do
    print_message "$YELLOW" "What is the domain name you will be using for PocketBase (e.g., example.com)?"
    read -r DOMAIN
    
    if validate_domain "$DOMAIN"; then
        break
    else
        print_message "$RED" "Invalid domain name. Please enter a valid domain name."
    fi
done

# Prompt for subdomain
print_message "$YELLOW" "Do you want to use a subdomain? If so, enter the subdomain (e.g., www). Otherwise, leave blank:"
read -r SUBDOMAIN

# Prompt for PocketBase port
while true; do
    print_message "$YELLOW" "What port do you want PocketBase to listen on (default: 8090)?"
    read -r POCKETBASE_PORT
    
    if [ -z "$POCKETBASE_PORT" ]; then
        POCKETBASE_PORT=8090
        break
    elif validate_port "$POCKETBASE_PORT"; then
        break
    else
        print_message "$RED" "Invalid port number. Please enter a valid port number (1-65535)."
    fi
done

# Prompt for HTTPS
while true; do
    print_message "$YELLOW" "Do you want to enable HTTPS using Let's Encrypt? (y/n)"
    read -r ENABLE_HTTPS
    
    if validate_yes_no "$ENABLE_HTTPS"; then
        ENABLE_HTTPS=$(echo "$ENABLE_HTTPS" | tr '[:upper:]' '[:lower:]')
        break
    else
        print_message "$RED" "Invalid input. Please enter 'y' or 'n'."
    fi
done

# Prompt for rate limiting
while true; do
    print_message "$YELLOW" "Do you want to enable rate limiting to protect against brute-force attacks? (y/n)"
    read -r ENABLE_RATE_LIMITING
    
    if validate_yes_no "$ENABLE_RATE_LIMITING"; then
        ENABLE_RATE_LIMITING=$(echo "$ENABLE_RATE_LIMITING" | tr '[:upper:]' '[:lower:]')
        break
    else
        print_message "$RED" "Invalid input. Please enter 'y' or 'n'."
    fi
done

# If rate limiting is enabled, prompt for rate limit and burst size
if [ "$ENABLE_RATE_LIMITING" = "y" ]; then
    while true; do
        print_message "$YELLOW" "What is the maximum number of requests per second you want to allow? (Recommended: 10r/s)"
        read -r RATE_LIMIT
        
        if validate_rate_limit "$RATE_LIMIT"; then
            break
        else
            print_message "$RED" "Invalid rate limit. Please enter a valid rate limit (e.g., 10r/s)."
        fi
    done
    
    while true; do
        print_message "$YELLOW" "What is the burst size you want to allow? (Recommended: 20)"
        read -r RATE_LIMIT_BURST
        
        if validate_numeric "$RATE_LIMIT_BURST"; then
            break
        else
            print_message "$RED" "Invalid burst size. Please enter a valid number."
        fi
    done
fi

# Prompt for security settings
while true; do
    print_message "$YELLOW" "Do you want to configure advanced security settings? (y/n)"
    read -r CONFIGURE_SECURITY
    
    if validate_yes_no "$CONFIGURE_SECURITY"; then
        CONFIGURE_SECURITY=$(echo "$CONFIGURE_SECURITY" | tr '[:upper:]' '[:lower:]')
        break
    else
        print_message "$RED" "Invalid input. Please enter 'y' or 'n'."
    fi
done

# If security settings are enabled, prompt for additional options
if [ "$CONFIGURE_SECURITY" = "y" ]; then
    while true; do
        print_message "$YELLOW" "Do you want to automatically block requests with suspicious User-Agents? (y/n)"
        read -r BLOCK_SUSPICIOUS_UAS
        
        if validate_yes_no "$BLOCK_SUSPICIOUS_UAS"; then
            BLOCK_SUSPICIOUS_UAS=$(echo "$BLOCK_SUSPICIOUS_UAS" | tr '[:upper:]' '[:lower:]')
            break
        else
            print_message "$RED" "Invalid input. Please enter 'y' or 'n'."
        fi
    done
fi

# Set public URL
if [ -n "$SUBDOMAIN" ]; then
    if [ "$ENABLE_HTTPS" = "y" ]; then
        PUBLIC_URL="https://$SUBDOMAIN.$DOMAIN"
    else
        PUBLIC_URL="http://$SUBDOMAIN.$DOMAIN"
    fi
else
    if [ "$ENABLE_HTTPS" = "y" ]; then
        PUBLIC_URL="https://$DOMAIN"
    else
        PUBLIC_URL="http://$DOMAIN"
    fi
fi

# Display installation summary
print_section "Installation Summary"
print_message "$BLUE" "Domain: $DOMAIN"
if [ -n "$SUBDOMAIN" ]; then
    print_message "$BLUE" "Subdomain: $SUBDOMAIN"
fi
print_message "$BLUE" "PocketBase Port: $POCKETBASE_PORT"
print_message "$BLUE" "Public URL: $PUBLIC_URL"
print_message "$BLUE" "HTTPS Enabled: $ENABLE_HTTPS"
print_message "$BLUE" "Rate Limiting Enabled: $ENABLE_RATE_LIMITING"
if [ "$ENABLE_RATE_LIMITING" = "y" ]; then
    print_message "$BLUE" "Rate Limit: $RATE_LIMIT"
    print_message "$BLUE" "Burst Size: $RATE_LIMIT_BURST"
fi
print_message "$BLUE" "Advanced Security: $CONFIGURE_SECURITY"
if [ "$CONFIGURE_SECURITY" = "y" ]; then
    print_message "$BLUE" "Block Suspicious User-Agents: $BLOCK_SUSPICIOUS_UAS"
fi

# Confirm installation
print_message "$YELLOW" "Do you want to proceed with the installation? (y/n)"
read -r CONFIRM
if [ "$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')" != "y" ]; then
    print_message "$RED" "Installation cancelled."
    exit 0
fi

# Start installation
print_section "Starting Installation"

# Update system
update_system

# Install dependencies
install_dependencies

# Create PocketBase user
create_pocketbase_user

# Install PocketBase
install_pocketbase

# Configure firewall
configure_firewall

# Configure Nginx
configure_nginx

# Configure HTTPS if enabled
if [ "$ENABLE_HTTPS" = "y" ]; then
    configure_https
fi

# Configure fail2ban if security settings are enabled
if [ "$CONFIGURE_SECURITY" = "y" ] && [ "$CONFIGURE_FAIL2BAN" = "y" ]; then
    configure_fail2ban
fi

# Create systemd service
create_systemd_service

# Create backup cron job
if [ "$ENABLE_BACKUPS" = "y" ]; then
    create_backup_cron
fi

# Display installation summary and admin setup URL
display_summary

exit 0
