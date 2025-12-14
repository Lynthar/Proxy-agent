#!/usr/bin/env bash
# English Language File

# System messages
MSG_SCRIPT_NOT_SUPPORTED="This script does not support this system. Please provide the logs below to the developer."
MSG_CPU_NOT_SUPPORTED="This CPU architecture is not supported"
MSG_DEFAULT_AMD64="Unable to identify CPU architecture, defaulting to amd64/x86_64"
MSG_NON_ROOT_USER="Non-root user detected, will use sudo to execute commands..."
MSG_SELINUX_NOTICE="SELinux is detected as enabled. Please manually disable it (e.g., set SELINUX=disabled in /etc/selinux/config and reboot)."

# Progress messages
MSG_PROGRESS="Progress"
MSG_INSTALL_TOOLS="Installing tools"
MSG_INSTALL_ACME="Installing acme.sh"
MSG_INSTALL_NGINX="Installing Nginx"
MSG_APPLY_CERT="Applying TLS certificate"
MSG_INSTALL_XRAY="Installing Xray"
MSG_INSTALL_SINGBOX="Installing sing-box"
MSG_CONFIG_XRAY="Configuring Xray"
MSG_CONFIG_SINGBOX="Configuring sing-box"
MSG_ADD_USERS="Adding users"

# Status messages
MSG_SUCCESS="Success"
MSG_FAILED="Failed"
MSG_COMPLETE="Complete"
MSG_ERROR="Error"
MSG_WARNING="Warning"
MSG_NOTICE="Notice"
MSG_RUNNING="Running"
MSG_NOT_RUNNING="Not running"
MSG_INSTALLED="Installed"
MSG_NOT_INSTALLED="Not installed"
MSG_ENABLED="Enabled"
MSG_NOT_ENABLED="Not enabled"

# Core messages
MSG_CORE_XRAY="Core: Xray-core"
MSG_CORE_SINGBOX="Core: sing-box"
MSG_CURRENT_CORE="Current core"
MSG_CORE_VERSION="Core version"

# Menu items
MSG_MENU_MAIN="Main Menu"
MSG_MENU_ACCOUNT="Account Management"
MSG_MENU_INSTALL="Install"
MSG_MENU_UNINSTALL="Uninstall"
MSG_MENU_UPDATE="Update"
MSG_MENU_CONFIG="Configuration"
MSG_MENU_CERT="Certificate Management"
MSG_MENU_ROUTING="Routing Management"
MSG_MENU_SUBSCRIPTION="Subscription Management"
MSG_MENU_LOGS="View Logs"
MSG_MENU_EXIT="Exit"
MSG_MENU_RETURN="Return to Main Menu"

# Input prompts
MSG_PROMPT_SELECT="Please select"
MSG_PROMPT_ENTER="Please enter"
MSG_PROMPT_CONFIRM="Please confirm"
MSG_PROMPT_DOMAIN="Please enter domain"
MSG_PROMPT_PORT="Please enter port"
MSG_PROMPT_PATH="Please enter path"
MSG_PROMPT_USE_LAST_CONFIG="Previous installation configuration found. Use it? [y/n]"
MSG_PROMPT_CONTINUE="Continue? [y/n]"

# Port messages
MSG_PORT_OPEN_SUCCESS="Port opened successfully"
MSG_PORT_OPEN_FAILED="Port failed to open"
MSG_PORT_CONFLICT="Port conflict"
MSG_PORT_OCCUPIED="Port is occupied"

# Certificate messages
MSG_CERT_VALID="Certificate valid"
MSG_CERT_EXPIRED="Certificate expired"
MSG_CERT_ABOUT_EXPIRE="Certificate about to expire"
MSG_CERT_APPLY="Apply certificate"
MSG_CERT_RENEW="Renew certificate"
MSG_CERT_DAYS_REMAINING="Days remaining"

# Domain messages
MSG_DOMAIN_VERIFY="Verify domain"
MSG_DOMAIN_MISMATCH="Domain DNS IP does not match current server IP"
MSG_DOMAIN_CHECK_HINT="Please check if domain resolution is effective and correct"
MSG_DNS_RESOLVED="DNS resolved IP"
MSG_DOMAIN_VERIFY_PASS="Domain IP verification passed"

# Installation messages
MSG_INSTALL_START="Starting installation"
MSG_INSTALL_COMPLETE="Installation complete"
MSG_INSTALL_FAILED="Installation failed"
MSG_UNINSTALL_COMPLETE="Uninstall complete"
MSG_UPDATE_COMPLETE="Update complete"

# Configuration messages
MSG_CONFIG_SAVED="Configuration saved"
MSG_CONFIG_LOADED="Configuration loaded"
MSG_CONFIG_BACKUP="Configuration backed up"
MSG_CONFIG_RESTORE="Configuration restored"
MSG_OTHER_CONFIG_DETECTED="Other configurations detected, keeping core"

# Error messages
MSG_ERR_GITHUB_FETCH="Failed to get GitHub file, please wait for GitHub to restore and try again"
MSG_ERR_ACME_BUG="acme.sh script has a bug"
MSG_ERR_IPV6_NAT64="For pure IPv6 machines, please set NAT64"
MSG_ERR_TROUBLESHOOT="Error troubleshooting"
MSG_ERR_WARP_ARM="Official WARP client does not support ARM architecture"
MSG_ERR_DNS_IPV6="Cannot get domain IPv6 address via DNS, exiting installation"
MSG_ERR_PORT_CHECK="Port not detected as open, exiting installation"
MSG_ERR_CLOUDFLARE_HINT="Please disable Cloudflare proxy and wait 3 minutes before retrying"
MSG_ERR_FIREWALL_HINT="Please check for web firewalls, such as Oracle Cloud"
MSG_ERR_NGINX_CONFLICT="Check if you have installed nginx with conflicting configuration"

# Panel messages
MSG_READING_BT_PANEL="Reading BT Panel configuration"
MSG_READING_1PANEL="Reading 1Panel configuration"

# Firewall messages
MSG_FIREWALL_ACTIVE="Firewall is active, adding open port"

# Service messages
MSG_SERVICE_START="Start service"
MSG_SERVICE_STOP="Stop service"
MSG_SERVICE_RESTART="Restart service"
MSG_BOOT_STARTUP="Boot startup"

# Clean messages
MSG_CLEAN_OLD="Clean old remnants"

# Subscription messages
MSG_SUBSCRIPTION_URL="Subscription URL"
MSG_SUBSCRIPTION_GENERATE="Generate subscription"

# WARP messages
MSG_INSTALL_WARP="Installing WARP"
MSG_WARP_FAILED="WARP installation failed"

# Protocol display
MSG_INSTALLED_PROTOCOLS="Installed protocols"
