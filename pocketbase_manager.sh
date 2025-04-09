#!/bin/bash

# ========================================================================
# PocketBase Service Manager
# ========================================================================
# This script provides a simple interface to manage the PocketBase service
# including viewing logs, checking status, and controlling the service.
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
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error_and_exit "Please run this script as root or with sudo" 1
    fi
}

# Function to display PocketBase service status
show_status() {
    print_section "PocketBase Service Status"
    systemctl status pocketbase
}

# Function to start PocketBase service
start_service() {
    print_section "Starting PocketBase Service"
    
    # Check if service is already running
    if systemctl is-active --quiet pocketbase; then
        print_message "$YELLOW" "PocketBase service is already running."
        return
    fi
    
    # Make sure the data directory has correct permissions
    if [ -d "/opt/pocketbase/pb_data" ]; then
        chown -R pocketbase:pocketbase /opt/pocketbase/pb_data
        chmod -R 755 /opt/pocketbase/pb_data
    fi
    
    # Start the service
    systemctl start pocketbase
    sleep 2  # Give it a moment to start
    
    if systemctl is-active --quiet pocketbase; then
        print_message "$GREEN" "PocketBase service started successfully!"
    else
        print_message "$RED" "Failed to start PocketBase service."
        print_message "$YELLOW" "Checking service logs for errors:"
        journalctl -u pocketbase -n 10 --no-pager
    fi
}

# Function to stop PocketBase service
stop_service() {
    print_section "Stopping PocketBase Service"
    
    # Check if service is already stopped
    if ! systemctl is-active --quiet pocketbase; then
        print_message "$YELLOW" "PocketBase service is already stopped."
        return
    fi
    
    # Stop the service
    systemctl stop pocketbase
    sleep 2  # Give it a moment to stop
    
    if ! systemctl is-active --quiet pocketbase; then
        print_message "$GREEN" "PocketBase service stopped successfully!"
    else
        print_message "$RED" "Failed to stop PocketBase service."
        print_message "$YELLOW" "Trying to force stop the service..."
        systemctl kill pocketbase
        sleep 1
        
        if ! systemctl is-active --quiet pocketbase; then
            print_message "$GREEN" "PocketBase service force-stopped successfully!"
        else
            print_message "$RED" "Failed to force-stop PocketBase service."
            print_message "$YELLOW" "You may need to reboot the system."
        fi
    fi
}

# Function to restart PocketBase service
restart_service() {
    print_section "Restarting PocketBase Service"
    
    # Stop the service first
    stop_service
    
    # Make sure the data directory has correct permissions
    if [ -d "/opt/pocketbase/pb_data" ]; then
        chown -R pocketbase:pocketbase /opt/pocketbase/pb_data
        chmod -R 755 /opt/pocketbase/pb_data
    fi
    
    # Start the service
    systemctl start pocketbase
    sleep 3  # Give it a moment to start
    
    if systemctl is-active --quiet pocketbase; then
        print_message "$GREEN" "PocketBase service restarted successfully!"
    else
        print_message "$RED" "Failed to restart PocketBase service."
        print_message "$YELLOW" "Checking service logs for errors:"
        journalctl -u pocketbase -n 10 --no-pager
    fi
}

# Function to enable PocketBase service at boot
enable_service() {
    print_section "Enabling PocketBase Service at Boot"
    systemctl enable pocketbase
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "PocketBase service enabled at boot successfully!"
    else
        print_message "$RED" "Failed to enable PocketBase service at boot."
    fi
}

# Function to disable PocketBase service at boot
disable_service() {
    print_section "Disabling PocketBase Service at Boot"
    systemctl disable pocketbase
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "PocketBase service disabled at boot successfully!"
    else
        print_message "$RED" "Failed to disable PocketBase service at boot."
    fi
}

# Function to view PocketBase logs
view_logs() {
    print_section "PocketBase Service Logs"
    
    local lines=$1
    if [ -z "$lines" ]; then
        lines=50
    fi
    
    print_message "$BLUE" "Showing last $lines lines of logs:"
    journalctl -u pocketbase -n "$lines" --no-pager
}

# Function to view PocketBase logs in follow mode
follow_logs() {
    print_section "Following PocketBase Service Logs"
    print_message "$BLUE" "Press Ctrl+C to stop following logs."
    journalctl -u pocketbase -f
}

# Function to check if PocketBase is accessible
check_accessibility() {
    print_section "Checking PocketBase Accessibility"
    
    # Get the port from the service file
    local port=$(grep -oP 'ExecStart=.*--http="0.0.0.0:\K[0-9]+' /etc/systemd/system/pocketbase.service)
    
    if [ -z "$port" ]; then
        port=8090  # Default port if not found
    fi
    
    print_message "$BLUE" "Testing connection to PocketBase on port $port..."
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        print_message "$YELLOW" "curl is not installed. Installing..."
        apt-get update && apt-get install -y curl
    fi
    
    # Try to connect to PocketBase
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port)
    
    if [ "$response" = "200" ]; then
        print_message "$GREEN" "PocketBase is accessible on port $port!"
    else
        print_message "$RED" "PocketBase is not accessible on port $port. Response code: $response"
    fi
}

# Function to display Nginx configuration for PocketBase
show_nginx_config() {
    print_section "Nginx Configuration for PocketBase"
    
    # Find the Nginx configuration file for PocketBase
    local config_files=$(find /etc/nginx/sites-available -type f -exec grep -l "proxy_pass.*pocketbase" {} \;)
    
    if [ -z "$config_files" ]; then
        print_message "$YELLOW" "No Nginx configuration found for PocketBase."
        return
    fi
    
    for file in $config_files; do
        print_message "$BLUE" "Configuration file: $file"
        print_message "$CYAN" "$(cat $file)"
        echo
    done
}

# Function to clear all PocketBase logs
clear_logs() {
    print_section "Clearing PocketBase Logs"
    
    # Stop the service first to prevent new logs from being generated
    local was_active=false
    if systemctl is-active --quiet pocketbase; then
        was_active=true
        print_message "$YELLOW" "Stopping PocketBase service temporarily..."
        stop_service
    fi
    
    # Clear systemd journal logs for PocketBase
    print_message "$BLUE" "Clearing systemd journal logs for PocketBase..."
    journalctl --vacuum-time=1s --unit=pocketbase
    
    # Clear PocketBase internal logs if they exist
    if [ -d "/opt/pocketbase/logs" ]; then
        print_message "$BLUE" "Clearing PocketBase internal log files..."
        rm -f /opt/pocketbase/logs/*.log
    fi
    
    # Clear Nginx logs related to PocketBase
    local nginx_log_files=$(find /var/log/nginx -type f -name "*pocketbase*" 2>/dev/null)
    if [ -n "$nginx_log_files" ]; then
        print_message "$BLUE" "Clearing Nginx logs related to PocketBase..."
        for log_file in $nginx_log_files; do
            > "$log_file"
            print_message "$CYAN" "Cleared: $log_file"
        done
    fi
    
    # Restart the service if it was active before
    if [ "$was_active" = true ]; then
        print_message "$YELLOW" "Restarting PocketBase service..."
        start_service
    fi
    
    print_message "$GREEN" "All PocketBase logs have been cleared successfully!"
}

# Function to directly run PocketBase binary
run_pocketbase() {
    print_section "Running PocketBase Binary Directly"
    
    # Check if PocketBase is already running
    if pgrep -f "/opt/pocketbase/pocketbase" > /dev/null; then
        print_message "$YELLOW" "PocketBase is already running directly."
        return
    fi
    
    # Make sure the data directory has correct permissions
    if [ -d "/opt/pocketbase/pb_data" ]; then
        chown -R pocketbase:pocketbase /opt/pocketbase/pb_data
        chmod -R 755 /opt/pocketbase/pb_data
    fi
    
    # Get the port from the service file
    local port=$(grep -oP 'ExecStart=.*--http="0.0.0.0:\K[0-9]+' /etc/systemd/system/pocketbase.service)
    if [ -z "$port" ]; then
        port=8090  # Default port if not found
    fi
    
    print_message "$BLUE" "Starting PocketBase on port $port..."
    print_message "$YELLOW" "Press Ctrl+C to stop PocketBase when done."
    
    # Run PocketBase directly
    su - pocketbase -c "cd /opt/pocketbase && ./pocketbase serve --http='0.0.0.0:$port'"
}

# Function to stop directly running PocketBase binary
stop_pocketbase_binary() {
    print_section "Stopping PocketBase Binary"
    
    # Check if PocketBase is running
    local pocketbase_pid=$(pgrep -f "/opt/pocketbase/pocketbase")
    if [ -z "$pocketbase_pid" ]; then
        print_message "$YELLOW" "PocketBase binary is not running directly."
        return
    fi
    
    print_message "$BLUE" "Stopping PocketBase binary (PID: $pocketbase_pid)..."
    kill $pocketbase_pid
    
    # Wait for process to terminate
    for i in {1..5}; do
        if ! pgrep -f "/opt/pocketbase/pocketbase" > /dev/null; then
            print_message "$GREEN" "PocketBase binary stopped successfully!"
            return
        fi
        sleep 1
    done
    
    # Force kill if still running
    if pgrep -f "/opt/pocketbase/pocketbase" > /dev/null; then
        print_message "$YELLOW" "PocketBase did not stop gracefully. Force killing..."
        pkill -9 -f "/opt/pocketbase/pocketbase"
        
        if ! pgrep -f "/opt/pocketbase/pocketbase" > /dev/null; then
            print_message "$GREEN" "PocketBase binary force-stopped successfully!"
        else
            print_message "$RED" "Failed to stop PocketBase binary."
        fi
    fi
}

# Function to restart directly running PocketBase binary
restart_pocketbase_binary() {
    print_section "Restarting PocketBase Binary"
    
    # Stop PocketBase binary
    stop_pocketbase_binary
    
    # Start PocketBase binary again
    run_pocketbase
}

# Function to display help
show_help() {
    print_section "PocketBase Service Manager Help"
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  status              Show PocketBase service status"
    echo "  start               Start PocketBase service"
    echo "  stop                Stop PocketBase service"
    echo "  restart             Restart PocketBase service"
    echo "  enable              Enable PocketBase service at boot"
    echo "  disable             Disable PocketBase service at boot"
    echo "  logs [LINES]        View PocketBase logs (default: last 50 lines)"
    echo "  follow-logs         Follow PocketBase logs in real-time"
    echo "  clear-logs          Clear all PocketBase logs"
    echo "  check               Check if PocketBase is accessible"
    echo "  nginx-config        Show Nginx configuration for PocketBase"
    echo "  run-binary          Run PocketBase binary directly (foreground)"
    echo "  stop-binary         Stop directly running PocketBase binary"
    echo "  restart-binary      Restart directly running PocketBase binary"
    echo "  help                Display this help message"
    echo
    echo "Examples:"
    echo "  $0 status           # Show service status"
    echo "  $0 logs 100         # Show last 100 lines of logs"
    echo "  $0 clear-logs       # Clear all PocketBase logs"
    echo "  $0 run-binary       # Run PocketBase directly in foreground"
}

# Main script execution
check_root

case "$1" in
    status)
        show_status
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    enable)
        enable_service
        ;;
    disable)
        disable_service
        ;;
    logs)
        view_logs "$2"
        ;;
    follow-logs)
        follow_logs
        ;;
    clear-logs)
        clear_logs
        ;;
    check)
        check_accessibility
        ;;
    nginx-config)
        show_nginx_config
        ;;
    run-binary)
        run_pocketbase
        ;;
    stop-binary)
        stop_pocketbase_binary
        ;;
    restart-binary)
        restart_pocketbase_binary
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        # If no arguments or invalid argument, show menu
        clear
        print_message "$CYAN" "
╔═══════════════════════════════════════════════════╗
║           PocketBase Service Manager              ║
╚═══════════════════════════════════════════════════╝"
        echo
        print_message "$BLUE" "Please select an option:"
        echo
        print_message "$YELLOW" "1) Show service status"
        print_message "$YELLOW" "2) Start service"
        print_message "$YELLOW" "3) Stop service"
        print_message "$YELLOW" "4) Restart service"
        print_message "$YELLOW" "5) Enable service at boot"
        print_message "$YELLOW" "6) Disable service at boot"
        print_message "$YELLOW" "7) View logs"
        print_message "$YELLOW" "8) Follow logs in real-time"
        print_message "$YELLOW" "9) Clear all logs"
        print_message "$YELLOW" "10) Check accessibility"
        print_message "$YELLOW" "11) Show Nginx configuration"
        print_message "$YELLOW" "12) Run PocketBase binary directly"
        print_message "$YELLOW" "13) Stop PocketBase binary"
        print_message "$YELLOW" "14) Restart PocketBase binary"
        print_message "$YELLOW" "0) Exit"
        echo
        read -p "Enter your choice [0-14]: " choice
        
        case $choice in
            1) show_status ;;
            2) start_service ;;
            3) stop_service ;;
            4) restart_service ;;
            5) enable_service ;;
            6) disable_service ;;
            7) 
                read -p "How many lines of logs to show? [50]: " lines
                lines=${lines:-50}
                view_logs "$lines" 
                ;;
            8) follow_logs ;;
            9) clear_logs ;;
            10) check_accessibility ;;
            11) show_nginx_config ;;
            12) run_pocketbase ;;
            13) stop_pocketbase_binary ;;
            14) restart_pocketbase_binary ;;
            0) exit 0 ;;
            *) 
                print_message "$RED" "Invalid option!"
                exit 1
                ;;
        esac
        ;;
esac

exit 0
