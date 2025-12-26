#!/usr/bin/env bash
# =============================================================================
# English Language File
# v2ray-agent i18n System
# =============================================================================

# =============================================================================
# System Messages
# =============================================================================
MSG_SYS_NOT_SUPPORTED="This script does not support this system. Please provide the logs below to the developer"
MSG_SYS_CPU_NOT_SUPPORTED="This CPU architecture is not supported"
MSG_SYS_CPU_DEFAULT_AMD64="Unable to identify CPU architecture, defaulting to amd64/x86_64"
MSG_SYS_NON_ROOT="Non-root user detected, will use sudo to execute commands..."
MSG_SYS_SELINUX_NOTICE="SELinux is enabled. Please disable it manually (set SELINUX=disabled in /etc/selinux/config and reboot)"

# =============================================================================
# Menu
# =============================================================================
MSG_MENU_TITLE="Multi-Protocol Proxy Script"
MSG_MENU_AUTHOR="Author"
MSG_MENU_VERSION="Version"
MSG_MENU_GITHUB="Github"
MSG_MENU_DESC="Description"
MSG_MENU_INSTALL="Install"
MSG_MENU_REINSTALL="Reinstall"
MSG_MENU_COMBO_INSTALL="Custom Combination Install"
MSG_MENU_CHAIN_PROXY="Chain Proxy Management"
MSG_MENU_HYSTERIA2="Hysteria2 Management"
MSG_MENU_REALITY="REALITY Management"
MSG_MENU_TUIC="Tuic Management"
MSG_MENU_USER="User Management"
MSG_MENU_DISGUISE="Disguise Site Management"
MSG_MENU_CERT="Certificate Management"
MSG_MENU_CDN="CDN Node Management"
MSG_MENU_ROUTING="Routing Tools"
MSG_MENU_ADD_PORT="Add New Port"
MSG_MENU_BT="BT Download Management"
MSG_MENU_BLACKLIST="Domain Blacklist"
MSG_MENU_CORE="Core Management"
MSG_MENU_UPDATE_SCRIPT="Update Script"
MSG_MENU_BBR="Install BBR/DD Script"
MSG_MENU_UNINSTALL="Uninstall Script"
MSG_MENU_TOOL_MGMT="Tool Management"
MSG_MENU_VERSION_MGMT="Version Management"
MSG_MENU_SCRIPT_MGMT="Script Management"
MSG_MENU_EXIT="Exit"
MSG_MENU_RETURN="Return to Main Menu"

# =============================================================================
# Progress Messages
# =============================================================================
MSG_PROGRESS="Progress"
MSG_PROGRESS_STEP="Progress %s/%s"
MSG_PROG_INSTALL_TOOLS="Installing Tools"
MSG_PROG_INSTALL_NGINX="Installing Nginx"
MSG_PROG_INIT_NGINX="Initializing Nginx Certificate Configuration"
MSG_PROG_APPLY_CERT="Applying TLS Certificate"
MSG_PROG_GEN_PATH="Generating Random Path"
MSG_PROG_ADD_DISGUISE="Adding Disguise Site"
MSG_PROG_ADD_CRON="Adding Certificate Renewal Cron"
MSG_PROG_UPDATE_CERT="Updating Certificate"
MSG_PROG_INSTALL_XRAY="Installing Xray"
MSG_PROG_INSTALL_SINGBOX="Installing sing-box"
MSG_PROG_CONFIG_XRAY="Configuring Xray"
MSG_PROG_CONFIG_SINGBOX="Configuring sing-box"
MSG_PROG_VERIFY_SERVICE="Verifying Service Status"
MSG_PROG_CONFIG_BOOT="Configuring Boot Startup"
MSG_PROG_INIT_HYSTERIA2="Initializing Hysteria2 Configuration"
MSG_PROG_PORT_HOPPING="Port Hopping"
MSG_PROG_XRAY_VERSION="Xray Version Management"
MSG_PROG_SINGBOX_VERSION="sing-box Version Management"
MSG_PROG_SCAN_REALITY="Scanning Reality Domains"

# =============================================================================
# Status Messages
# =============================================================================
MSG_STATUS_SUCCESS="Success"
MSG_STATUS_FAILED="Failed"
MSG_STATUS_COMPLETE="Complete"
MSG_STATUS_ERROR="Error"
MSG_STATUS_WARNING="Warning"
MSG_STATUS_NOTICE="Notice"
MSG_STATUS_RUNNING="Running"
MSG_STATUS_NOT_RUNNING="Not Running"
MSG_STATUS_INSTALLED="Installed"
MSG_STATUS_NOT_INSTALLED="Not Installed"
MSG_STATUS_ENABLED="Enabled"
MSG_STATUS_NOT_ENABLED="Not Enabled"
MSG_STATUS_VALID="Valid"
MSG_STATUS_INVALID="Invalid"
MSG_STATUS_EXPIRED="Expired"

# =============================================================================
# Input Prompts
# =============================================================================
MSG_PROMPT_SELECT="Please select"
MSG_PROMPT_ENTER="Please enter"
MSG_PROMPT_CONFIRM="Please confirm [y/n]"
MSG_PROMPT_CONTINUE="Continue? [y/n]"
MSG_PROMPT_DOMAIN="Please enter domain"
MSG_PROMPT_DOMAIN_EXAMPLE="Please enter domain, e.g.: example.com"
MSG_PROMPT_PORT="Please enter port"
MSG_PROMPT_PORT_RANDOM="Please enter port [Enter for random 10000-30000]"
MSG_PROMPT_PORT_DEFAULT="Please enter port [default: %s], custom port available [Enter for default]"
MSG_PROMPT_PATH="Please enter path"
MSG_PROMPT_PATH_CUSTOM="Please enter custom path [e.g.: alone], no slash needed, [Enter] for random"
MSG_PROMPT_UUID="Please enter custom UUID [must be valid], [Enter] for random"
MSG_PROMPT_EMAIL="Please enter custom username [must be valid], [Enter] for random"
MSG_PROMPT_USE_LAST="Previous installation config detected. Use it? [y/n]"
MSG_PROMPT_USE_LAST_DOMAIN="Previous domain detected. Use it? [y/n]"
MSG_PROMPT_USE_LAST_PORT="Previous port detected. Use it? [y/n]"
MSG_PROMPT_USE_LAST_PATH="Previous path detected. Use it? [y/n]"
MSG_PROMPT_USE_LAST_UUID="Previous user config detected. Use it? [y/n]"
MSG_PROMPT_USE_LAST_KEY="Previous PublicKey/PrivateKey detected. Use it? [y/n]"
MSG_PROMPT_INPUT_NUM="Please enter number to select"
MSG_PROMPT_SELECT_ERROR="Invalid selection, please try again"
MSG_PROMPT_REINSTALL="Reinstall? [y/n]"
MSG_PROMPT_UPDATE="Update/Upgrade? [y/n]"
MSG_PROMPT_OVERWRITE="Overwrite existing config? [y/n]"

# =============================================================================
# Installation Messages
# =============================================================================
MSG_INSTALL_START="Starting installation"
MSG_INSTALL_COMPLETE="Installation complete"
MSG_INSTALL_FAILED="Installation failed"
MSG_INSTALL_SUCCESS="Installation successful"
MSG_INSTALL_SKIP="Skipping installation"
MSG_INSTALL_CHECKING="Checking and installing updates [may be slow on new machines, restart manually if no response]"
MSG_INSTALL_TOOL="Installing %s"
MSG_INSTALL_DETECT_NO_NGINX="Detected service that doesn't require Nginx, skipping installation"
MSG_INSTALL_DETECT_NO_CERT="Detected service that doesn't require certificate, skipping installation"

MSG_UNINSTALL_COMPLETE="Uninstall complete"
MSG_UNINSTALL_CONFIRM="Confirm uninstallation? [y/n]"
MSG_UNINSTALL_SINGBOX="sing-box uninstall complete"

MSG_UPDATE_COMPLETE="Update complete"
MSG_UPDATE_ABANDON="Update cancelled"
MSG_UPDATE_REINSTALL_ABANDON="Reinstall cancelled"
MSG_UPDATE_ROLLBACK_ABANDON="Rollback cancelled"

# =============================================================================
# Core/Protocol Messages
# =============================================================================
MSG_CORE_XRAY="Xray-core"
MSG_CORE_SINGBOX="sing-box"
MSG_CORE_CURRENT="Core: %s"
MSG_CORE_CURRENT_RUNNING="Core: %s [Running]"
MSG_CORE_CURRENT_STOPPED="Core: %s [Stopped]"
MSG_CORE_VERSION="Core Version"
MSG_CORE_VERSION_CURRENT="Current version: %s"
MSG_CORE_VERSION_LATEST="Latest version: %s"
MSG_CORE_VERSION_SAME="Current version is same as latest. Reinstall? [y/n]"
MSG_CORE_DOWNLOAD_FAILED="Core download failed. Retry? [y/n]"
MSG_CORE_NOT_DETECTED="Installation directory not found. Please run script to install"

MSG_PROTOCOLS_INSTALLED="Installed protocols"
MSG_PROTOCOL_DEPENDS="Depends on %s"

# Xray Version Management Menu
MSG_XRAY_UPGRADE="Upgrade Xray-core"
MSG_XRAY_UPGRADE_PRE="Upgrade Xray-core Pre-release"
MSG_XRAY_ROLLBACK="Rollback Xray-core"
MSG_XRAY_STOP="Stop Xray-core"
MSG_XRAY_START="Start Xray-core"
MSG_XRAY_RESTART="Restart Xray-core"
MSG_XRAY_UPDATE_GEO="Update geosite/geoip"
MSG_XRAY_AUTO_GEO="Set auto-update geo files [daily at midnight]"
MSG_XRAY_VIEW_LOG="View Logs"
MSG_XRAY_ROLLBACK_NOTICE_1="Can only rollback to the last 5 versions"
MSG_XRAY_ROLLBACK_NOTICE_2="No guarantee that rollback will work properly"
MSG_XRAY_ROLLBACK_NOTICE_3="If rollback version doesn't support current config, connection will fail. Proceed with caution"
MSG_XRAY_ROLLBACK_CONFIRM="Rollback to version %s, continue? [y/n]"
MSG_XRAY_ROLLBACK_INPUT="Please enter version to rollback"
MSG_XRAY_UPDATE_CONFIRM="Latest version: %s, update? [y/n]"
MSG_XRAY_GEO_SOURCE="Source: https://github.com/Loyalsoldier/v2ray-rules-dat"

# sing-box Version Management Menu
MSG_SINGBOX_UPGRADE="Upgrade sing-box"
MSG_SINGBOX_STOP="Stop sing-box"
MSG_SINGBOX_START="Start sing-box"
MSG_SINGBOX_RESTART="Restart sing-box"
MSG_SINGBOX_LOG_ENABLE="Enable Logs"
MSG_SINGBOX_LOG_DISABLE="Disable Logs"
MSG_SINGBOX_VIEW_LOG="View Logs"

# =============================================================================
# Port Messages
# =============================================================================
MSG_PORT="Port"
MSG_PORT_CURRENT="Port: %s"
MSG_PORT_OPEN_SUCCESS="Port %s opened successfully"
MSG_PORT_OPEN_FAILED="Port %s failed to open"
MSG_PORT_CONFLICT="Port conflict"
MSG_PORT_OCCUPIED="Port %s is occupied. Please close it before installation"
MSG_PORT_EMPTY="Port cannot be empty"
MSG_PORT_INVALID="Invalid port"
MSG_PORT_INPUT_ERROR="Port input error"
MSG_PORT_DETECTED_OPEN="Port %s detected as open"
MSG_PORT_NOT_DETECTED="Port %s not detected as open, exiting installation"
MSG_PORT_BT_CONFLICT="Enter port [cannot be same as BT Panel/1Panel port, Enter for random]"
MSG_PORT_RANGE="Port range: %s"

# Port Hopping
MSG_PORT_HOP_TITLE="Port Hopping"
MSG_PORT_HOP_ADD="Add Port Hopping"
MSG_PORT_HOP_DEL="Delete Port Hopping"
MSG_PORT_HOP_VIEW="View Port Hopping"
MSG_PORT_HOP_NOTICE_1="Only supports Hysteria2 and Tuic"
MSG_PORT_HOP_NOTICE_2="Port hopping start: 30000"
MSG_PORT_HOP_NOTICE_3="Port hopping end: 40000"
MSG_PORT_HOP_NOTICE_4="Select a range within 30000-40000"
MSG_PORT_HOP_NOTICE_5="Recommended: around 1000 ports"
MSG_PORT_HOP_NOTICE_6="Avoid overlapping ranges with other port hopping settings"
MSG_PORT_HOP_INPUT="Enter port hopping range, e.g. [30000-31000]"
MSG_PORT_HOP_EMPTY="Range cannot be empty"
MSG_PORT_HOP_INVALID="Invalid range"
MSG_PORT_HOP_SUCCESS="Port hopping added successfully"
MSG_PORT_HOP_FAILED="Port hopping failed to add"
MSG_PORT_HOP_DEL_SUCCESS="Deleted successfully"
MSG_PORT_HOP_CURRENT="Current port hopping range: %s-%s"
MSG_PORT_HOP_NOT_SET="Port hopping not configured"
MSG_PORT_HOP_NO_FIREWALL="firewalld not running, cannot set port hopping"
MSG_PORT_HOP_NO_IPTABLES="Cannot identify iptables tool, cannot use port hopping, exiting installation"
MSG_PORT_HOP_ALREADY_SET="Already added, cannot add again. Delete first to re-add"

# =============================================================================
# Certificate Messages
# =============================================================================
MSG_CERT_VALID="Certificate valid"
MSG_CERT_EXPIRED="Certificate expired"
MSG_CERT_ABOUT_EXPIRE="Certificate about to expire"
MSG_CERT_DAYS_LEFT="%s days remaining"
MSG_CERT_DETECTED="Certificate detected"
MSG_CERT_APPLY="Apply certificate"
MSG_CERT_RENEW="Renew certificate"
MSG_CERT_RENEW_AUTO="Auto-renewal on last day before expiry. Manual renewal if auto fails"
MSG_CERT_CHECK_DATE="Certificate check date: %s"
MSG_CERT_GEN_DATE="Certificate generation date: %s"
MSG_CERT_GEN_DAYS="Days since generation: %s"
MSG_CERT_REMAINING="Days remaining: %s"
MSG_CERT_REGENERATE="Regenerate certificate"
MSG_CERT_CUSTOM_NOTICE="Custom certificate detected, cannot perform renew operation"
MSG_CERT_NOT_EXPIRED="Select [n] if not expired or using custom certificate"
MSG_CERT_TLS_SUCCESS="TLS generated successfully"
MSG_CERT_TLS_FAILED="TLS installation failed, please check acme logs"
MSG_CERT_TLS_DEPEND="TLS certificate installation requires port 80"
MSG_CERT_NO_API="Not using API for certificate"
MSG_CERT_API_DNS="Use DNS API for certificate [supports NAT]? [y/n]"
MSG_CERT_API_WILDCARD="Use *.%s for API wildcard certificate? [y/n]"
MSG_CERT_API_NOT_SUPPORT="This domain doesn't support wildcard certificate. Recommended format: [xx.xx.xx]"
MSG_CERT_CRON_SUCCESS="Certificate renewal cron added successfully"
MSG_CERT_CRON_EXISTS="Auto-renewal cron already exists, do not add again"
MSG_CERT_GEO_CRON_SUCCESS="Geo file update cron added successfully"

# ACME
MSG_ACME_NOT_INSTALLED="acme.sh not installed"
MSG_ACME_INSTALL_FAILED="acme installation failed"
MSG_ACME_ERROR_TROUBLESHOOT="Error troubleshooting"
MSG_ACME_ERROR_GITHUB="Failed to get GitHub file. Please wait for GitHub to recover. Check status at [https://www.githubstatus.com/]"
MSG_ACME_ERROR_BUG="acme.sh script has a bug. Check [https://github.com/acmesh-official/acme.sh] issues"
MSG_ACME_ERROR_IPV6="For pure IPv6 machines, please set NAT64. Run the command below. If still not working, try other NAT64"
MSG_ACME_EMAIL_INVALID="Email failed SSL provider verification, please re-enter"
MSG_ACME_EMAIL_INPUT="Please enter email address"
MSG_ACME_EMAIL_RETRY="Re-enter email address? [y/n]"
MSG_ACME_EMAIL_FORMAT="Please enter valid email format [e.g.: username@example.com]"
MSG_ACME_EMAIL_ADDED="Added successfully"

# DNS API
MSG_DNS_API_SELECT="Please select DNS provider"
MSG_DNS_CLOUDFLARE="Cloudflare [default]"
MSG_DNS_ALIYUN="Aliyun"
MSG_DNS_CF_TOKEN_HINT="Please create API Token with DNS edit permission in Cloudflare console and enter CF_Token/CF_Account_ID"
MSG_DNS_INPUT_TOKEN="Please enter API Token"
MSG_DNS_INPUT_EMPTY="Input is empty, please re-enter"
MSG_DNS_INPUT_ALI_KEY="Please enter Ali Key"
MSG_DNS_INPUT_ALI_SECRET="Please enter Ali Secret"
MSG_DNS_GEN_CERT="Generating certificate via DNS API"

# SSL Provider
MSG_SSL_SELECT="Please select SSL certificate provider"
MSG_SSL_LETSENCRYPT="Let's Encrypt [default]"
MSG_SSL_ZEROSSL="ZeroSSL"
MSG_SSL_BUYPASS="Buypass [DNS not supported]"
MSG_SSL_BUYPASS_NOT_SUPPORT="Buypass does not support API certificate issuance"
MSG_SSL_GEN_CERT="Generating certificate"

# =============================================================================
# Domain Messages
# =============================================================================
MSG_DOMAIN="Domain"
MSG_DOMAIN_CURRENT="Domain: %s"
MSG_DOMAIN_VERIFY="Verify domain"
MSG_DOMAIN_VERIFYING="Checking domain IP"
MSG_DOMAIN_MISMATCH="Domain DNS IP does not match server IP"
MSG_DOMAIN_CHECK_HINT="Please check if domain resolution is effective and correct"
MSG_DOMAIN_SERVER_IP="Current VPS IP: %s"
MSG_DOMAIN_DNS_IP="DNS resolved IP: %s"
MSG_DOMAIN_VERIFY_PASS="Domain IP verification passed"
MSG_DOMAIN_CHECK_CORRECT="Current domain IP is correct"
MSG_DOMAIN_NOT_DETECTED="Domain IP not detected"
MSG_DOMAIN_CHECK_LIST="Please check the following"
MSG_DOMAIN_CHECK_1="Check if domain is spelled correctly"
MSG_DOMAIN_CHECK_2="Check if domain DNS resolution is correct"
MSG_DOMAIN_CHECK_3="If resolution is correct, wait for DNS propagation (~3 minutes)"
MSG_DOMAIN_CHECK_4="If Nginx startup error, manually start nginx to view error. Submit issues if unable to resolve"
MSG_DOMAIN_REINSTALL_HINT="If all above settings are correct, try reinstalling with a clean system"
MSG_DOMAIN_ABNORMAL="Abnormal return value detected. Recommend manually uninstalling nginx and re-running script"
MSG_DOMAIN_ABNORMAL_RESULT="Abnormal result: %s"
MSG_DOMAIN_MULTI_IP="Multiple IPs detected. Please confirm Cloudflare proxy is disabled"
MSG_DOMAIN_CF_WAIT="Disable proxy and wait 3 minutes before retrying"
MSG_DOMAIN_DETECTED_IP="Detected IPs: [%s]"
MSG_DOMAIN_EMPTY="Domain cannot be empty"
MSG_DOMAIN_INPUT="Domain"

# =============================================================================
# Service Control Messages
# =============================================================================
MSG_SVC_START="Start %s"
MSG_SVC_STOP="Stop %s"
MSG_SVC_RESTART="Restart %s"
MSG_SVC_START_SUCCESS="%s started successfully"
MSG_SVC_START_FAILED="%s failed to start"
MSG_SVC_STOP_SUCCESS="%s stopped successfully"
MSG_SVC_STOP_FAILED="%s failed to stop"
MSG_SVC_BOOT_CONFIG="Configuring %s boot startup"
MSG_SVC_BOOT_SUCCESS="%s boot startup configured"
MSG_SVC_VERIFY_SUCCESS="Service started successfully"
MSG_SVC_VERIFY_FAILED="Service failed to start, please check terminal for logs"

# Nginx
MSG_NGINX_START_SUCCESS="Nginx started successfully"
MSG_NGINX_START_FAILED="Nginx failed to start"
MSG_NGINX_STOP_SUCCESS="Nginx stopped successfully"
MSG_NGINX_UNINSTALL="nginx uninstall complete"
MSG_NGINX_UNINSTALL_CONFIRM="Current Nginx version doesn't support gRPC, installation will fail. Uninstall and reinstall Nginx? [y/n]"
MSG_NGINX_DEL_DEFAULT="Deleting Nginx default configuration"
MSG_NGINX_DEV_LOG="Please provide logs below to developer"
MSG_NGINX_SELINUX_CHECK="Checking SELinux port status"
MSG_NGINX_SELINUX_PORT_OK="http_port_t %s port opened successfully"

# Manual Command Prompts
MSG_MANUAL_CMD_XRAY="Please manually run [/etc/v2ray-agent/xray/xray -confdir /etc/v2ray-agent/xray/conf] and provide error logs for feedback"
MSG_MANUAL_CMD_SINGBOX_MERGE="Please manually run [ /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ ] to view error logs"
MSG_MANUAL_CMD_SINGBOX_RUN="If above command has no errors, manually run [ /etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json ] to view error logs"
MSG_MANUAL_CMD_KILL="Please manually run [ps -ef|grep -v grep|grep %s|awk '{print \$2}'|xargs kill -9]"

# =============================================================================
# Configuration Messages
# =============================================================================
MSG_CONFIG_SAVED="Configuration saved"
MSG_CONFIG_LOADED="Configuration loaded"
MSG_CONFIG_BACKUP="Configuration backed up"
MSG_CONFIG_RESTORE="Configuration restored"
MSG_CONFIG_OTHER_DETECTED="Other configurations detected, keeping %s core"
MSG_CONFIG_DEL_SUCCESS="%s configuration deleted successfully"
MSG_CONFIG_USE_SUCCESS="Applied successfully"
MSG_CONFIG_REALITY="Configure VLESS+Reality"
MSG_CONFIG_PROTOCOL="Configure %s"
MSG_CONFIG_PROTOCOL_PORT="Configuring %s protocol port"
MSG_CONFIG_PORT_RESULT="%s port: %s"

# Path
MSG_PATH="Path"
MSG_PATH_CURRENT="path: %s"
MSG_PATH_WS_SUFFIX="Custom path cannot end with 'ws', cannot distinguish routing path"

# =============================================================================
# Error Messages
# =============================================================================
MSG_ERR_GITHUB_FETCH="Failed to get GitHub file, please wait for GitHub to recover"
MSG_ERR_ACME_BUG="acme.sh script has a bug"
MSG_ERR_IPV6_NAT64="For pure IPv6 machines, please set NAT64"
MSG_ERR_TROUBLESHOOT="Error troubleshooting"
MSG_ERR_WARP_ARM="Official WARP client does not support ARM architecture"
MSG_ERR_DNS_IPV4="Cannot get domain IPv4 address via DNS"
MSG_ERR_DNS_IPV6="Cannot get domain IPv6 address via DNS, exiting installation"
MSG_ERR_DNS_TRY_IPV6="Trying to check domain IPv6 address"
MSG_ERR_PORT_CHECK="Port not detected as open, exiting installation"
MSG_ERR_CLOUDFLARE_HINT="Please disable Cloudflare proxy and wait 3 minutes before retrying"
MSG_ERR_FIREWALL_HINT="Please check for web firewalls, such as Oracle Cloud"
MSG_ERR_NGINX_CONFLICT="Check if you installed nginx with conflicting configuration. Try DD clean system and retry"
MSG_ERR_LOG="Error log: %s, please submit this error log via issues"
MSG_ERR_FILE_PATH_INVALID="File path is invalid"
MSG_ERR_NOT_EMPTY="%s cannot be empty"
MSG_ERR_INPUT_INVALID="Invalid input, please try again"
MSG_ERR_JSON_PARSE="%s parsing failed, removed. Please check input and retry"
MSG_ERR_UUID_READ="UUID read error, generating random"
MSG_ERR_PRIVATE_KEY_INVALID="Invalid Private Key"
MSG_ERR_IP_READ="Cannot read correct IP"
MSG_ERR_IP_GET="Cannot get IP"
MSG_ERR_CERT_DEPEND="Certificate required. To install %s, please first install protocol with TLS"

# =============================================================================
# WARP Messages
# =============================================================================
MSG_WARP_INSTALL="Installing WARP"
MSG_WARP_INSTALL_FAILED="WARP installation failed"
MSG_WARP_START_SUCCESS="WARP started successfully"
MSG_WARP_NOT_INSTALLED="warp-reg not installed. Install? [y/n]"

# =============================================================================
# Panel Messages
# =============================================================================
MSG_PANEL_BT_READ="Reading BT Panel configuration"
MSG_PANEL_1PANEL_READ="Reading 1Panel configuration"

# =============================================================================
# Firewall Messages
# =============================================================================
MSG_FIREWALL_ACTIVE="Firewall is active, adding open port"

# =============================================================================
# Subscription Messages
# =============================================================================
MSG_SUB_URL="Subscription URL"
MSG_SUB_GENERATE="Generate Subscription"

# =============================================================================
# User Management Messages
# =============================================================================
MSG_USER_ADD="Add User"
MSG_USER_ADD_COUNT="Please enter number of users to add"
MSG_USER_DEL="Delete User"
MSG_USER_DEL_SELECT="Please select user number to delete [single deletion only]"
MSG_USER_INFO="%s: %s"

# =============================================================================
# Disguise Site Messages
# =============================================================================
MSG_DISGUISE_START="Adding disguise site"
MSG_DISGUISE_SUCCESS="Disguise site added successfully"
MSG_DISGUISE_REINSTALL="Disguise site detected. Reinstall? [y/n]"

# =============================================================================
# CDN Messages
# =============================================================================
MSG_CDN_INPUT="Please enter custom CDN IP or domain"

# =============================================================================
# Reality Messages
# =============================================================================
MSG_REALITY_CONFIG_SN="Configure client-available serverNames"
MSG_REALITY_NOTICE="Ensure selected Reality target domain supports TLS and is a commonly accessible site"
MSG_REALITY_INPUT_EXAMPLE="Example: addons.mozilla.org:443"
MSG_REALITY_INPUT_DOMAIN="Enter target domain, [Enter] for random domain, default port 443"
MSG_REALITY_USE_DOMAIN="Use %s as Reality target domain? [y/n]"
MSG_REALITY_USE_LAST="Previous Reality domain detected. Use it? [y/n]"
MSG_REALITY_CLIENT_DOMAIN="Client-available domain: %s:%s"
MSG_REALITY_NOT_INSTALLED="Please install Reality protocol first and confirm serverName/public key are configured"
MSG_REALITY_CF_WARNING="Domain is hosted on Cloudflare with proxy enabled. Using this may allow others to use your VPS traffic [not recommended]"
MSG_REALITY_IGNORE_RISK="Ignore risk, continue"
MSG_REALITY_GEN_MLDSA65="Generating Reality mldsa65"
MSG_REALITY_X25519_SUPPORT="Target domain supports X25519MLKEM768 but certificate length insufficient, ignoring ML-DSA-65"
MSG_REALITY_X25519_NOT_SUPPORT="Target domain doesn't support X25519MLKEM768, ignoring ML-DSA-65"
MSG_REALITY_USE_LAST_SEED="Previous Seed/Verify detected. Use it? [y/n]"
MSG_REALITY_INPUT_PRIVATE_KEY="Enter Private Key [Enter to auto-generate]"

# Reality Scanner
MSG_REALITY_SCAN_IPV4="Scan IPv4"
MSG_REALITY_SCAN_IPV6="Scan IPv6"
MSG_REALITY_SCAN_NOTICE_1="After scanning, verify results comply with regulations. Personal responsibility applies"
MSG_REALITY_SCAN_NOTICE_2="Some IDCs prohibit scanning (e.g., BandwagonHost). Personal responsibility applies"
MSG_REALITY_SCAN_CONFIRM="Some IDCs prohibit scanning. Continue at your own risk? [y/n]"
MSG_REALITY_SCAN_RESULT="Results stored in /etc/v2ray-agent/xray/reality_scan/result.log"
MSG_REALITY_IP_CONFIRM="Is IP correct? [y/n]"

# =============================================================================
# Hysteria2 Messages
# =============================================================================
MSG_HYSTERIA2_PORT="Enter Hysteria port [Enter for random 10000-30000], cannot conflict with other services"
MSG_HYSTERIA2_DOWN_SPEED="Enter local bandwidth peak download speed (default: 100, unit: Mbps)"
MSG_HYSTERIA2_UP_SPEED="Enter local bandwidth peak upload speed (default: 50, unit: Mbps)"
MSG_HYSTERIA2_DOWN_RESULT="Download speed: %s"
MSG_HYSTERIA2_UP_RESULT="Upload speed: %s"
MSG_HYSTERIA2_OBFS_HINT="Enable obfuscation (obfs)? Leave empty to disable, enter password to enable salamander obfs"
MSG_HYSTERIA2_OBFS_INPUT="Obfs password (leave empty to disable)"
MSG_HYSTERIA2_OBFS_ENABLED="Obfuscation enabled"
MSG_HYSTERIA2_OBFS_DISABLED="Obfuscation disabled"
MSG_HYSTERIA2_MANAGE="Hysteria2 Management"
MSG_HYSTERIA2_DEBUG="Please manually run [/etc/v2ray-agent/hysteria/hysteria --log-level debug -c /etc/v2ray-agent/hysteria/conf/config.json server] to view error logs"

# =============================================================================
# Tuic Messages
# =============================================================================
MSG_TUIC_PORT="Enter Tuic port [Enter for random 10000-30000], cannot conflict with other services"
MSG_TUIC_PORT_RESULT="Port: %s"
MSG_TUIC_ALGO="Algorithm: %s"
MSG_TUIC_ALGO_SELECT="Please select algorithm type"
MSG_TUIC_ALGO_BBR="bbr (default)"
MSG_TUIC_ALGO_CUBIC="cubic"
MSG_TUIC_ALGO_NEWRENO="new_reno"
MSG_TUIC_USE_LAST_ALGO="Previous algorithm detected. Use it? [y/n]"
MSG_TUIC_MANAGE="Tuic Management"

# =============================================================================
# SS2022 Messages
# =============================================================================
MSG_SS2022_PORT="Enter Shadowsocks 2022 port [Enter for random 10000-30000]"
MSG_SS2022_PORT_RESULT="Port: %s"
MSG_SS2022_METHOD_SELECT="Please select encryption method"
MSG_SS2022_METHOD_1="2022-blake3-aes-128-gcm [recommended, shorter key]"
MSG_SS2022_METHOD_2="2022-blake3-aes-256-gcm"
MSG_SS2022_METHOD_3="2022-blake3-chacha20-poly1305"
MSG_SS2022_METHOD_RESULT="Encryption method: %s"
MSG_SS2022_KEY_GEN="Server key auto-generated"
MSG_SS2022_CONFIG_DONE="Shadowsocks 2022 configuration complete"
MSG_SS2022_USE_LAST_PORT="Previous port %s detected. Use it? [y/n]"

# =============================================================================
# TCP_Brutal Messages
# =============================================================================
MSG_TCP_BRUTAL_USE="Use TCP_Brutal? [y/n]"
MSG_TCP_BRUTAL_DOWN="Enter local bandwidth peak download speed (default: 100, unit: Mbps)"
MSG_TCP_BRUTAL_UP="Enter local bandwidth peak upload speed (default: 50, unit: Mbps)"
MSG_TCP_BRUTAL_INIT="Initializing TCP_Brutal configuration"

# =============================================================================
# Chain Proxy Messages
# =============================================================================
MSG_CHAIN_CODE="Config code"
MSG_CHAIN_EXIT_IP="Exit node IP"
MSG_CHAIN_EXIT_PORT="Exit node port"
MSG_CHAIN_EXIT_KEY="Key"
MSG_CHAIN_EXIT_METHOD="Encryption method"
MSG_CHAIN_DOWNSTREAM="Config code"
MSG_CHAIN_PUBLIC_IP="Public IP"
MSG_CHAIN_LIMIT_IP="Please select"
MSG_CHAIN_LIMIT_ALLOW="Enter allowed entry node IP"

# Multi-Chain Split Routing Messages
MSG_MULTI_CHAIN_TITLE="Configure Entry Node (Multi-Chain Split Routing Mode)"
MSG_MULTI_CHAIN_DESC="This mode allows routing different traffic to different exit nodes"
MSG_MULTI_CHAIN_EXAMPLE="Example: Netflix → US Exit, OpenAI → HK Exit"
MSG_MULTI_CHAIN_SINGLE_EXISTS="Existing single-chain configuration detected"
MSG_MULTI_CHAIN_UNINSTALL_HINT="To use multi-chain mode, please uninstall existing chain proxy first"
MSG_MULTI_CHAIN_MENU_PATH="Menu path: Chain Proxy Management → Uninstall Chain Proxy"
MSG_MULTI_CHAIN_EXISTS="Existing multi-chain configuration detected"
MSG_MULTI_CHAIN_ADD_MORE="Continue adding new chains"
MSG_MULTI_CHAIN_RECONFIGURE="Reconfigure (will clear existing config)"
MSG_MULTI_CHAIN_CANCEL="Cancel"
MSG_MULTI_CHAIN_CONFIRM_CLEAR="Confirm clearing existing multi-chain config? [y/n]"
MSG_MULTI_CHAIN_SELECT_MODE="Select configuration mode:"
MSG_MULTI_CHAIN_MODE_INTERACTIVE="Add chains one by one (Recommended)"
MSG_MULTI_CHAIN_MODE_BATCH="Batch import config codes"
MSG_MULTI_CHAIN_ADD_CHAIN="Add chain"
MSG_MULTI_CHAIN_ADD_FAILED="Chain add failed or cancelled"
MSG_MULTI_CHAIN_CONTINUE_ADD="Continue adding chains? [y/n]"
MSG_MULTI_CHAIN_NO_CHAIN="No chains added, configuration cancelled"
MSG_MULTI_CHAIN_BATCH_TITLE="Batch Import Config Codes"
MSG_MULTI_CHAIN_BATCH_HINT="Paste config codes line by line, one per line"
MSG_MULTI_CHAIN_BATCH_END="Enter empty line when done"
MSG_MULTI_CHAIN_PARSE_FAILED="Config code parsing failed, skipped"
MSG_MULTI_CHAIN_ADD_SUCCESS="Chain [%s] added successfully (%s:%s)"
MSG_MULTI_CHAIN_IMPORT_NONE="No chains imported, configuration cancelled"
MSG_MULTI_CHAIN_IMPORT_SUCCESS="Successfully imported %s chains"
MSG_MULTI_CHAIN_CONFIGURE_RULES="Configure routing rules now? [y/n]"
MSG_MULTI_CHAIN_STEP_IMPORT="Step 1/3: Import Configuration"
MSG_MULTI_CHAIN_PASTE_CODE="Paste exit/relay node config code:"
MSG_MULTI_CHAIN_STEP_NAME="Step 2/3: Name Chain"
MSG_MULTI_CHAIN_CHAIN_INFO="Chain info:"
MSG_MULTI_CHAIN_TARGET="Target"
MSG_MULTI_CHAIN_PROTOCOL="Protocol"
MSG_MULTI_CHAIN_INPUT_NAME="Enter chain name (alphanumeric and underscore only, Enter for default: %s):"
MSG_MULTI_CHAIN_NAME_EXISTS="Chain name already exists, please use a different name"
MSG_MULTI_CHAIN_NAME_INVALID="Invalid chain name, only alphanumeric and underscore allowed"
MSG_MULTI_CHAIN_STEP_RULES="Step 3/3: Configure Routing Rules"
MSG_MULTI_CHAIN_RULE_HINT="Select traffic types for this chain (multiple allowed, comma-separated):"
MSG_MULTI_CHAIN_RULE_STREAMING="Streaming (Netflix/Disney+/YouTube/...)"
MSG_MULTI_CHAIN_RULE_AI="AI Services (OpenAI/Bing/...)"
MSG_MULTI_CHAIN_RULE_SOCIAL="Social Media (Telegram/Twitter/...)"
MSG_MULTI_CHAIN_RULE_DEV="Developer (GitHub/GitLab/...)"
MSG_MULTI_CHAIN_RULE_GAMING="Gaming (Steam/Epic/...)"
MSG_MULTI_CHAIN_RULE_GOOGLE="Google Services"
MSG_MULTI_CHAIN_RULE_CUSTOM="Custom domain rules"
MSG_MULTI_CHAIN_RULE_NONE="Skip for now (configure later)"
MSG_MULTI_CHAIN_CUSTOM_DOMAIN="Enter custom domains (wildcards supported, comma-separated):"
MSG_MULTI_CHAIN_CUSTOM_EXAMPLE="Example: *.example.com, api.test.org"
MSG_MULTI_CHAIN_CONFIG_SUCCESS="Chain configuration complete"
MSG_MULTI_CHAIN_CONFIG_SAVED="Configuration saved"
MSG_MULTI_CHAIN_STATUS_TITLE="Multi-Chain Split Routing Status"
MSG_MULTI_CHAIN_TOTAL_CHAINS="Total chains: %s"
MSG_MULTI_CHAIN_DEFAULT_CHAIN="Default chain: %s"
MSG_MULTI_CHAIN_NO_DEFAULT="No default chain set (unmatched traffic goes direct)"
MSG_MULTI_CHAIN_LIST="Chain list:"
MSG_MULTI_CHAIN_RULES="Routing rules:"
MSG_MULTI_CHAIN_RULE_ALL="All unmatched traffic"
MSG_MULTI_CHAIN_RULE_PENDING="Pending configuration"
MSG_MULTI_CHAIN_RULE_CUSTOM_DOMAIN="Custom domains"
MSG_MULTI_CHAIN_TEST_TITLE="Multi-Chain Connectivity Test"
MSG_MULTI_CHAIN_TESTING="Testing all chains in parallel..."
MSG_MULTI_CHAIN_TEST_SUCCESS="✅ %s (%s) - Latency: %sms"
MSG_MULTI_CHAIN_TEST_FAILED="❌ %s (%s) - Connection failed"
MSG_MULTI_CHAIN_TEST_RESULT="Test result: %s/%s chains working"
MSG_MULTI_CHAIN_ADV_MENU="Multi-Chain Advanced Settings"
MSG_MULTI_CHAIN_ADV_ADD="Add new chain"
MSG_MULTI_CHAIN_ADV_REMOVE="Remove chain"
MSG_MULTI_CHAIN_ADV_DEFAULT="Set default chain"
MSG_MULTI_CHAIN_ADV_RULES="Manage routing rules"
MSG_MULTI_CHAIN_ADV_VIEW="View detailed config"
MSG_MULTI_CHAIN_SELECT_REMOVE="Select chain to remove:"
MSG_MULTI_CHAIN_CONFIRM_REMOVE="Confirm removing chain [%s]? [y/n]"
MSG_MULTI_CHAIN_REMOVED="Chain removed"
MSG_MULTI_CHAIN_SELECT_DEFAULT="Select default chain (unmatched traffic will use this chain):"
MSG_MULTI_CHAIN_DIRECT="Direct (unmatched traffic connects directly)"
MSG_MULTI_CHAIN_DEFAULT_SET="Default chain set to: %s"
MSG_MULTI_CHAIN_DEFAULT_DIRECT="Default chain set to direct connection"
MSG_MULTI_CHAIN_DETECTED="Multi-chain mode detected, %s chains configured"
MSG_MULTI_CHAIN_SINGLE_DETECTED="Single-chain mode detected"
MSG_MULTI_CHAIN_NOT_FOUND="No chain proxy configuration detected"
MSG_MULTI_CHAIN_DELETED="Multi-chain configuration deleted"

# =============================================================================
# Credential Input Messages
# =============================================================================
MSG_CRED_HINT="%s for configuring handshake credentials, can be entered manually/from file/from environment variable"
MSG_CRED_SELECT="Select %s input method (file or environment variable for automation)"
MSG_CRED_DIRECT="Direct input"
MSG_CRED_DIRECT_DEFAULT="Direct input [Enter for default]"
MSG_CRED_FROM_FILE="Read from file"
MSG_CRED_FROM_ENV="Read from environment variable"
MSG_CRED_FILE_PATH="Enter file path"
MSG_CRED_ENV_NAME="Enter environment variable name"

# =============================================================================
# BBR Messages
# =============================================================================
MSG_BBR_INSTALL="Install BBR"

# =============================================================================
# Routing Tools Messages
# =============================================================================
MSG_ROUTING_IPV6="IPv6 Routing"
MSG_ROUTING_DOMAIN="Domain Routing"
MSG_ROUTING_INPUT_DOMAIN="Enter domains as shown in example above"
MSG_ROUTING_CONFIRM="Confirm settings? [y/n]"

# =============================================================================
# Blacklist Messages
# =============================================================================
MSG_BLACKLIST_DOMAIN="Domain Blacklist"
MSG_BLACKLIST_INPUT="Enter domains as shown in example above"

# =============================================================================
# Log Messages
# =============================================================================
MSG_LOG_ACCESS="Access Log"
MSG_LOG_LEVEL="Log Level"
MSG_LOG_SELECT="Please select"

# =============================================================================
# Common Messages
# =============================================================================
MSG_NOTICE="Notice"
MSG_VERSION="Version"
MSG_DEFAULT="Default"
MSG_CUSTOM="Custom"
MSG_RANDOM="Random"
MSG_YES="Yes"
MSG_NO="No"
MSG_ENABLED="Enabled"
MSG_DISABLED="Disabled"
MSG_CANCEL="Cancel"
MSG_CONFIRM="Confirm"
MSG_BACK="Back"
MSG_NEXT="Next"
MSG_PREV="Previous"
MSG_FINISH="Finish"
MSG_LOADING="Loading..."
MSG_PROCESSING="Processing..."
MSG_PLEASE_WAIT="Please wait..."

# =============================================================================
# Client Output Format Messages
# =============================================================================
MSG_CLIENT_GENERAL="General Format"
MSG_CLIENT_FORMATTED="Formatted Plain Text"
MSG_CLIENT_QRCODE="QR Code"
MSG_CLIENT_JSON="General JSON"
MSG_CLIENT_LINK="Link"
MSG_CLIENT_PROTOCOL="Protocol Type"
MSG_CLIENT_ADDRESS="Address"
MSG_CLIENT_PORT="Port"
MSG_CLIENT_USER_ID="User ID"
MSG_CLIENT_SECURITY="Security"
MSG_CLIENT_TRANSPORT="Transport"
MSG_CLIENT_PATH="Path"
MSG_CLIENT_ACCOUNT="Account"
MSG_CLIENT_SNI="SNI"
MSG_CLIENT_FINGERPRINT="client-fingerprint"
MSG_CLIENT_FLOW="flow"
MSG_CLIENT_PUBLIC_KEY="publicKey"
MSG_CLIENT_SHORT_ID="shortId"
MSG_CLIENT_SERVER_NAME="serverNames"

# =============================================================================
# Script Version Management Messages
# =============================================================================
MSG_MENU_SCRIPT_VERSION="Script Version Management"
MSG_SCRIPT_VERSION_TITLE="Script Version Management"
MSG_SCRIPT_VERSION_CURRENT="Current Version"
MSG_SCRIPT_VERSION_UPDATE="Update Script"
MSG_SCRIPT_VERSION_ROLLBACK="Rollback Version"
MSG_SCRIPT_VERSION_BACKUP="Manual Backup"
MSG_SCRIPT_VERSION_LIST="View Backups"
MSG_SCRIPT_VERSION_BACK="Back to Main Menu"
MSG_SCRIPT_BACKUP_SUCCESS="Backup successful"
MSG_SCRIPT_BACKUP_FAILED="Backup failed"
MSG_SCRIPT_BACKUP_SKIP="Backup skipped (first install or no version available)"
MSG_SCRIPT_ROLLBACK_SELECT="Select version to rollback"
MSG_SCRIPT_ROLLBACK_LOCAL="Local Backup"
MSG_SCRIPT_ROLLBACK_GITHUB="GitHub Release"
MSG_SCRIPT_ROLLBACK_NO_VERSIONS="No versions available"
MSG_SCRIPT_ROLLBACK_CONFIRM="Confirm rollback to this version?"
MSG_SCRIPT_ROLLBACK_SUCCESS="Rollback successful"
MSG_SCRIPT_ROLLBACK_FAILED="Rollback failed"
MSG_SCRIPT_ROLLBACK_RESTART="Please run pasly to start the new version"
MSG_SCRIPT_BACKUP_BEFORE_UPDATE="Backing up current version before update..."
MSG_SCRIPT_BACKUP_COMPLETE="Backup complete"
MSG_SCRIPT_NO_BACKUPS="No local backups available"
MSG_SCRIPT_BACKUP_TIME="Backup Time"
MSG_SCRIPT_BACKUP_REASON="Backup Reason"
MSG_SCRIPT_REASON_UPDATE="Auto backup before update"
MSG_SCRIPT_REASON_ROLLBACK="Auto backup before rollback"
MSG_SCRIPT_REASON_MANUAL="Manual backup"
MSG_SCRIPT_ROLLBACK_NOTE1="Rollback may be incompatible with current configuration"
MSG_SCRIPT_ROLLBACK_NOTE2="Recommend backing up important configs before rollback"
MSG_SCRIPT_ROLLBACK_NOTE3="Rollback will not affect installed proxy service configs"
MSG_SCRIPT_GITHUB_UNAVAILABLE="Unable to fetch GitHub version list"
MSG_CURRENT="Current"
MSG_NOTE="Notes"
