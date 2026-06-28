#!/bin/bash

# ============================================================
#  WordPress Site Creator
#  Debian/Ubuntu — Apache or Nginx — Multi-PHP support
# ============================================================

set -euo pipefail

# ── Colours ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

separator() {
    echo -e "${CYAN}──────────────────────────────────────────────────────${RESET}"
}

ask() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local value=""

    while [[ -z "$value" ]]; do
        if [[ -n "$default" ]]; then
            read -rp "$(echo -e "${BOLD}${prompt}${RESET} [${default}]: ")" value
            value="${value:-$default}"
        else
            read -rp "$(echo -e "${BOLD}${prompt}${RESET}: ")" value
        fi
        if [[ -z "$value" ]]; then
            warn "Value cannot be empty. Please try again."
        fi
    done

    printf -v "$var_name" '%s' "$value"
}

ask_secret() {
    local prompt="$1"
    local var_name="$2"
    local value=""

    while [[ -z "$value" ]]; do
        read -rsp "$(echo -e "${BOLD}${prompt}${RESET}: ")" value
        echo
        if [[ -z "$value" ]]; then
            warn "Value cannot be empty. Please try again."
        fi
    done

    printf -v "$var_name" '%s' "$value"
}

ask_yn() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-n}"
    local answer=""

    while true; do
        read -rp "$(echo -e "${BOLD}${prompt}${RESET} [y/n] (default: ${default}): ")" answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) printf -v "$var_name" 'yes'; return ;;
            n|no)  printf -v "$var_name" 'no';  return ;;
            *) warn "Please answer 'y' (yes) or 'n' (no)." ;;
        esac
    done
}

choose_menu() {
    local prompt="$1"
    local var_name="$2"
    shift 2
    local options=("$@")
    local choice=""

    echo -e "\n${BOLD}${prompt}${RESET}"
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${RESET} ${options[$i]}"
    done

    while true; do
        read -rp "$(echo -e "${BOLD}Choose an option [1-${#options[@]}]:${RESET} ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            printf -v "$var_name" '%s' "${options[$((choice-1))]}"
            return
        fi
        warn "Invalid option. Choose between 1 and ${#options[@]}."
    done
}

# ── Root check ───────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    die "This script must be run as root. Use: sudo $0"
fi

# ── Banner ───────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat <<'EOF'
  _    _               _  _____ _____
 | |  | |             | ||  __ \  __ \
 | |  | | ___  _ __ __| || |__) | |__) | __ ___  ___ ___
 | |/\| |/ _ \| '__/ _` ||  ___/|  _  / '__/ _ \/ __/ __|
 \  /\  / (_) | | | (_| || |    | | \ \ | |  __/\__ \__ \
  \/  \/ \___/|_|  \__,_||_|    |_|  \_\_|  \___||___/___/

               WordPress Site Creator — Debian/Ubuntu
EOF
echo -e "${RESET}"
separator

# ── Environment file ─────────────────────────────────────────
ENV_FILE="$(dirname "$(realpath "$0")")/wp.env"
ENV_LOADED=false

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    ENV_LOADED=true
    success "Environment file loaded: ${ENV_FILE}"
    info    "DB_USER, DB_PASS, DB_HOST, DB_PREFIX (and MySQL root credentials if set) will be taken from the file."
fi

# ════════════════════════════════════════════════════════════
#  SECTION 1: Site Information
# ════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}▸ Site Information${RESET}\n"

ask "Site domain (e.g.: mydomain.com)" DOMAIN
DOMAIN="${DOMAIN#www.}"  # normalize: strip leading www.
WEB_ROOT="/var/www/${DOMAIN}"

if [[ -d "$WEB_ROOT" ]]; then
    warn "Directory ${WEB_ROOT} already exists."
    ask_yn "Do you want to continue and overwrite its contents?" OVERWRITE "n"
    [[ "$OVERWRITE" == "no" ]] && die "Operation cancelled."
fi

# ════════════════════════════════════════════════════════════
#  SECTION 2: Database
# ════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}▸ Database Configuration${RESET}\n"

# Database name — always prompted to prevent accidental data loss
warn "The database name is always required interactively to prevent overwriting an existing database."
DB_NAME_DEFAULT="${DOMAIN//[.-]/_}"
while true; do
    ask "Database name" DB_NAME "$DB_NAME_DEFAULT"
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        warn "Invalid database name. Use only letters, numbers, and underscores (no spaces or special characters)."
    elif (( ${#DB_NAME} > 64 )); then
        warn "Database name must not exceed 64 characters."
    else
        break
    fi
done

# Database user
if [[ "$ENV_LOADED" == true && -n "${DB_USER:-}" ]]; then
    info "Database user loaded from env file: ${DB_USER}"
else
    ask "Database user" DB_USER "wp_${DOMAIN//[.-]/_}"
fi

# Database password
if [[ "$ENV_LOADED" == true && -n "${DB_PASS:-}" ]]; then
    info "Database password loaded from env file."
else
    ask_secret "Database user password" DB_PASS
fi

# Database host
if [[ "$ENV_LOADED" == true && -n "${DB_HOST:-}" ]]; then
    info "Database host loaded from env file: ${DB_HOST}"
else
    ask "Database host" DB_HOST "localhost"
fi

# Table prefix
if [[ "$ENV_LOADED" == true && -n "${DB_PREFIX:-}" ]]; then
    info "Table prefix loaded from env file: ${DB_PREFIX}"
else
    ask "Table prefix" DB_PREFIX "wp_"
fi

ask_yn "Automatically create the database and user (requires MySQL/MariaDB root access)?" CREATE_DB "y"

if [[ "$CREATE_DB" == "yes" ]]; then
    info "MySQL/MariaDB root access is required to create the database."
    if [[ "$ENV_LOADED" == true && -n "${MYSQL_ROOT_USER:-}" ]]; then
        info "MySQL root user loaded from env file: ${MYSQL_ROOT_USER}"
    else
        ask "MySQL/MariaDB root user" MYSQL_ROOT_USER "root"
    fi
    if [[ "$ENV_LOADED" == true && -n "${MYSQL_ROOT_PASS:-}" ]]; then
        info "MySQL root password loaded from env file."
    else
        ask_secret "MySQL/MariaDB root password" MYSQL_ROOT_PASS
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 3: Web Server
# ════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}▸ Web Server${RESET}\n"

choose_menu "Which web server do you want to configure?" WEB_SERVER \
    "Apache" \
    "Nginx" \
    "None (skip vhost configuration)"

if [[ "$WEB_SERVER" != "None (skip vhost configuration)" ]]; then
    ask_yn "Add www.${DOMAIN} alias?" ADD_WWW "y"
fi

# ════════════════════════════════════════════════════════════
#  SECTION 4: PHP Version
# ════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}▸ PHP Version${RESET}\n"

# Detect installed PHP versions
INSTALLED_PHPS=()
for v in 7.4 8.0 8.1 8.2 8.3 8.4; do
    if command -v "php${v}" &>/dev/null; then
        INSTALLED_PHPS+=("php${v}")
    fi
done

DEFAULT_PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "unknown")

if [[ ${#INSTALLED_PHPS[@]} -gt 0 ]]; then
    info "Detected PHP versions: ${INSTALLED_PHPS[*]}"
fi

echo -e "  System default version: ${BOLD}PHP ${DEFAULT_PHP_VERSION}${RESET}"

ask_yn "Do you want to specify a particular PHP version?" USE_CUSTOM_PHP "n"

if [[ "$USE_CUSTOM_PHP" == "yes" ]]; then
    ask "PHP version (e.g.: 8.2)" PHP_VERSION ""
    PHP_VERSION="${PHP_VERSION#php}"  # normalize: strip leading 'php'

    if ! command -v "php${PHP_VERSION}" &>/dev/null; then
        warn "php${PHP_VERSION} is not installed on this system."
        ask_yn "Do you want to continue anyway?" CONTINUE_PHP "n"
        [[ "$CONTINUE_PHP" == "no" ]] && die "Operation cancelled. Install PHP ${PHP_VERSION} and try again."
    fi

    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
else
    PHP_VERSION="$DEFAULT_PHP_VERSION"
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
fi

# ════════════════════════════════════════════════════════════
#  PRE-EXECUTION SUMMARY
# ════════════════════════════════════════════════════════════
echo ""
separator
echo -e "${BOLD}${CYAN}  CONFIGURATION SUMMARY${RESET}"
separator
echo -e "  ${BOLD}Domain:${RESET}       ${DOMAIN}"
echo -e "  ${BOLD}Directory:${RESET}    ${WEB_ROOT}"
echo -e "  ${BOLD}Database:${RESET}     ${DB_NAME} @ ${DB_HOST}"
echo -e "  ${BOLD}DB User:${RESET}      ${DB_USER}"
echo -e "  ${BOLD}Table prefix:${RESET} ${DB_PREFIX}"
echo -e "  ${BOLD}Create DB:${RESET}    ${CREATE_DB}"
echo -e "  ${BOLD}Web server:${RESET}   ${WEB_SERVER}"
if [[ "$WEB_SERVER" != "None (skip vhost configuration)" ]]; then
    echo -e "  ${BOLD}WWW alias:${RESET}    ${ADD_WWW}"
fi
echo -e "  ${BOLD}PHP version:${RESET}  ${PHP_VERSION}"
separator

ask_yn "Confirm installation with this configuration?" CONFIRM "y"
[[ "$CONFIRM" == "no" ]] && die "Operation cancelled by user."

# ════════════════════════════════════════════════════════════
#  STEP 1: Create project directory
# ════════════════════════════════════════════════════════════
echo ""
separator
info "Step 1/6 — Creating project directory..."

mkdir -p "$WEB_ROOT"
success "Directory created: ${WEB_ROOT}"

# ════════════════════════════════════════════════════════════
#  STEP 2: Download and install WordPress
# ════════════════════════════════════════════════════════════
separator
info "Step 2/6 — Downloading the latest version of WordPress..."

TMP_WP="/tmp/wp-latest-$$.tar.gz"
TMP_DIR="/tmp/wp-extract-$$"

if command -v curl &>/dev/null; then
    curl -fsSL "https://wordpress.org/latest.tar.gz" -o "$TMP_WP" \
        || die "Failed to download WordPress."
elif command -v wget &>/dev/null; then
    wget -q "https://wordpress.org/latest.tar.gz" -O "$TMP_WP" \
        || die "Failed to download WordPress."
else
    die "curl or wget is required to download WordPress."
fi

info "Extracting files..."
mkdir -p "$TMP_DIR"
tar -xzf "$TMP_WP" -C "$TMP_DIR"
cp -a "${TMP_DIR}/wordpress/." "$WEB_ROOT/"

rm -rf "$TMP_WP" "$TMP_DIR"
success "WordPress installed at ${WEB_ROOT}"

# ════════════════════════════════════════════════════════════
#  STEP 3: Create MySQL/MariaDB database and user
# ════════════════════════════════════════════════════════════
separator
info "Step 3/6 — Configuring database..."

if [[ "$CREATE_DB" == "yes" ]]; then
    MYSQL_CMD="mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASS}"

    # Safety check: warn if the WordPress DB user is the same as the admin user
    if [[ "$DB_USER" == "$MYSQL_ROOT_USER" ]]; then
        warn "WARNING: The database user '${DB_USER}' is the same as the MySQL admin user."
        warn "This is a security risk — WordPress will connect to MySQL with admin credentials."
        ask_yn "Do you want to continue anyway?" CONTINUE_ADMIN_USER "n"
        [[ "$CONTINUE_ADMIN_USER" == "no" ]] && die "Operation cancelled. Use a dedicated database user for WordPress."
    fi

    # Safety check: abort if the database already exists to prevent data corruption
    DB_EXISTS=$(mysql -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASS}" \
        --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';" 2>/dev/null || echo "0")
    if [[ "${DB_EXISTS// /}" -gt 0 ]]; then
        die "Database '${DB_NAME}' already exists. Choose a different name to prevent corrupting existing data."
    fi

    $MYSQL_CMD -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
        || die "Failed to create the database."

    # Check if the MySQL user already exists to avoid modifying an existing user
    # and potentially affecting their permissions on other databases
    DB_USER_EXISTS=$(mysql -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASS}" \
        --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM mysql.user WHERE User='${DB_USER}' AND Host='${DB_HOST}';" 2>/dev/null || echo "0")

    if [[ "${DB_USER_EXISTS// /}" -gt 0 ]]; then
        warn "MySQL user '${DB_USER}'@'${DB_HOST}' already exists — skipping user creation."

        # Check if the user already has global privileges (ON *.*).
        # If so, they already have access to the new database — no GRANT needed.
        # Running GRANT on a user with global privileges can overwrite their grant
        # record in mysql.user and cause loss of options like WITH GRANT OPTION.
        HAS_GLOBAL_PRIV=$(mysql -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASS}" \
            --batch --skip-column-names \
            -e "SELECT Select_priv FROM mysql.user WHERE User='${DB_USER}' AND Host='${DB_HOST}';" 2>/dev/null || echo "N")

        if [[ "${HAS_GLOBAL_PRIV// /}" == "Y" ]]; then
            info "User '${DB_USER}'@'${DB_HOST}' already has global privileges — no GRANT needed for '${DB_NAME}'."
            success "Database '${DB_NAME}' created. Existing user '${DB_USER}' already has access."
        else
            warn "User '${DB_USER}'@'${DB_HOST}' does not have global privileges."
            ask_yn "Grant '${DB_USER}'@'${DB_HOST}' access to '${DB_NAME}'?" GRANT_EXISTING "y"
            if [[ "$GRANT_EXISTING" == "yes" ]]; then
                $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';" \
                    || die "Failed to grant privileges."
                $MYSQL_CMD -e "FLUSH PRIVILEGES;" \
                    || die "Failed to flush privileges."
                success "Database '${DB_NAME}' created and access granted to existing user '${DB_USER}'."
            else
                warn "No privileges granted. Ensure '${DB_USER}'@'${DB_HOST}' has access to '${DB_NAME}' before the WordPress site can connect."
            fi
        fi
    else
        $MYSQL_CMD -e "CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';" \
            || die "Failed to create the database user."

        $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';" \
            || die "Failed to grant privileges."

        $MYSQL_CMD -e "FLUSH PRIVILEGES;" \
            || die "Failed to flush privileges."

        success "Database '${DB_NAME}' and user '${DB_USER}' created successfully."
    fi
else
    warn "Database creation skipped. Make sure to create it manually."
fi

# ════════════════════════════════════════════════════════════
#  STEP 4: Generate wp-config.php
# ════════════════════════════════════════════════════════════
separator
info "Step 4/6 — Generating wp-config.php..."

# Fetch salts from the WordPress API
WP_SALTS=$(curl -fsSL "https://api.wordpress.org/secret-key/1.1/salt/" 2>/dev/null \
    || echo "/* ERROR: Could not fetch salts automatically. Generate them manually at https://api.wordpress.org/secret-key/1.1/salt/ */")

cat > "${WEB_ROOT}/wp-config.php" <<PHP
<?php
/**
 * WordPress configuration file — generated by create-wordpress.sh
 */

// ── Database ────────────────────────────────────────────────
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  '' );

// ── Auth keys & salts ───────────────────────────────────────
${WP_SALTS}

// ── Table prefix ────────────────────────────────────────────
\$table_prefix = '${DB_PREFIX}';

// ── Filesystem ──────────────────────────────────────────────
define( 'FS_METHOD', 'direct' );

// ── Security ────────────────────────────────────────────────
define( 'DISALLOW_FILE_EDIT', true );

// ── Debugging (disabled in production) ──────────────────────
define( 'WP_DEBUG',         false );
define( 'WP_DEBUG_LOG',     false );
define( 'WP_DEBUG_DISPLAY', false );

// ── HTTPS ───────────────────────────────────────────────────
define( 'FORCE_SSL_ADMIN', false );

// ── Paths ───────────────────────────────────────────────────
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
PHP

chmod 640 "${WEB_ROOT}/wp-config.php"
success "wp-config.php generated successfully."

# ════════════════════════════════════════════════════════════
#  STEP 5: File system permissions
# ════════════════════════════════════════════════════════════
separator
info "Step 5/6 — Applying permissions..."

chown -R www-data:www-data "$WEB_ROOT"
find "$WEB_ROOT" -type d -exec chmod 755 {} \;
find "$WEB_ROOT" -type f -exec chmod 644 {} \;
chmod 640 "${WEB_ROOT}/wp-config.php"

success "Permissions applied successfully."

# ════════════════════════════════════════════════════════════
#  STEP 6: Vhost configuration
# ════════════════════════════════════════════════════════════
separator
info "Step 6/6 — Configuring web server..."

# ── Apache vhost generator ───────────────────────────────────
create_apache_vhost() {
    local conf_dir="/etc/apache2/sites-available"
    local conf_file="${conf_dir}/${DOMAIN}.conf"

    local server_alias_block=""
    if [[ "$ADD_WWW" == "yes" ]]; then
        server_alias_block="    ServerAlias www.${DOMAIN}"
    fi

    cat > "$conf_file" <<APACHECONF
<VirtualHost *:80>
    ServerName   ${DOMAIN}
${server_alias_block}

    DocumentRoot ${WEB_ROOT}
    DirectoryIndex index.php index.html

    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        # PHP-FPM via socket
        <FilesMatch \\.php\$>
            SetHandler "proxy:unix:${PHP_FPM_SOCK}|fcgi://localhost"
        </FilesMatch>
    </Directory>

    # Logs
    ErrorLog  \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
APACHECONF

    success "Apache vhost created: ${conf_file}"

    if command -v a2ensite &>/dev/null; then
        a2ensite "${DOMAIN}.conf" &>/dev/null
        success "Site enabled in Apache."
    fi

    if command -v a2enmod &>/dev/null; then
        a2enmod rewrite proxy_fcgi setenvif &>/dev/null
    fi

    if systemctl is-active --quiet apache2; then
        systemctl reload apache2
        success "Apache reloaded."
    else
        warn "Apache is not running. Start it with: systemctl start apache2"
    fi
}

# ── Nginx vhost generator ────────────────────────────────────
create_nginx_vhost() {
    local conf_dir="/etc/nginx/sites-available"
    local conf_file="${conf_dir}/${DOMAIN}.conf"
    local enabled_dir="/etc/nginx/sites-enabled"

    local server_name_line="${DOMAIN}"
    if [[ "$ADD_WWW" == "yes" ]]; then
        server_name_line="www.${DOMAIN} ${DOMAIN}"
    fi

    cat > "$conf_file" <<NGINXCONF
server {
    listen 80;
    listen [::]:80;

    server_name ${server_name_line};
    root        ${WEB_ROOT};
    index       index.php index.html;

    # Logs
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Deny access to sensitive files
    location ~* /(?:uploads|files|wp-content)/.*\.php\$ {
        deny all;
    }

    location ~ /\. {
        deny all;
    }

    location = /xmlrpc.php {
        deny all;
    }

    # Static assets cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|eot)\$ {
        expires max;
        log_not_found off;
    }

    # PHP-FPM
    location ~ \.php\$ {
        include        snippets/fastcgi-php.conf;
        fastcgi_pass   unix:${PHP_FPM_SOCK};
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }
}
NGINXCONF

    success "Nginx vhost created: ${conf_file}"

    if [[ -d "$enabled_dir" ]]; then
        ln -sf "$conf_file" "${enabled_dir}/${DOMAIN}.conf"
        success "Site enabled in Nginx."
    fi

    if systemctl is-active --quiet nginx; then
        nginx -t && systemctl reload nginx
        success "Nginx reloaded."
    else
        warn "Nginx is not running. Start it with: systemctl start nginx"
    fi
}

# ── Run based on selection ───────────────────────────────────
case "$WEB_SERVER" in
    "Apache")
        create_apache_vhost
        ;;
    "Nginx")
        create_nginx_vhost
        ;;
    *)
        warn "Vhost creation skipped."
        ;;
esac

# ── PHP-FPM restart ──────────────────────────────────────────
if [[ "$USE_CUSTOM_PHP" == "yes" ]] && systemctl list-units --quiet "${PHP_FPM_SERVICE}.service" &>/dev/null; then
    if systemctl is-active --quiet "${PHP_FPM_SERVICE}"; then
        systemctl restart "${PHP_FPM_SERVICE}"
        success "PHP-FPM ${PHP_VERSION} restarted."
    else
        warn "${PHP_FPM_SERVICE} is not active. Start it with: systemctl start ${PHP_FPM_SERVICE}"
    fi
fi

# ════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ════════════════════════════════════════════════════════════
echo ""
separator
echo -e "${BOLD}${GREEN}  INSTALLATION COMPLETE${RESET}"
separator
echo ""
echo -e "  ${BOLD}Site:${RESET}       http://${DOMAIN}"
echo -e "  ${BOLD}Directory:${RESET}  ${WEB_ROOT}"
echo -e "  ${BOLD}PHP:${RESET}        ${PHP_VERSION}"
echo ""
echo -e "  ${BOLD}${YELLOW}Next steps:${RESET}"
echo -e "   1. Point the DNS of ${DOMAIN} to this server."

if [[ "$WEB_SERVER" == "None (skip vhost configuration)" ]]; then
    echo -e "   2. Configure your web server manually pointing to ${WEB_ROOT}"
fi

echo -e "   3. Complete the WordPress installation at: http://${DOMAIN}/wp-admin/install.php"
echo ""
separator
