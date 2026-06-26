# WordPress Site Creator

Interactive Bash script that provisions a full WordPress site on Debian/Ubuntu servers. It handles directory creation, WordPress download, database setup, `wp-config.php` generation, file permissions, and web server virtual host configuration — all in a single run.

## Requirements

- Debian or Ubuntu server
- Root access (`sudo`)
- `curl` or `wget`
- MySQL or MariaDB
- Apache or Nginx
- PHP (7.4 – 8.4)

## Files

| File | Description |
|---|---|
| `create-wordpress.sh` | Main script |
| `wp.env` | Optional environment file for preset variables |

## Usage

```bash
sudo ./create-wordpress.sh
```

The script will guide you through four sections interactively before executing anything.

## Environment file (`wp.env`)

To avoid being prompted for the same database credentials on every run, fill in `wp.env` (located in the same directory as the script):

```bash
# Database connection
DB_USER="wp_user"
DB_PASS="your_secure_password_here"
DB_HOST="localhost"
DB_PREFIX="wp_"

# MySQL/MariaDB root access — optional, uncomment to enable
# MYSQL_ROOT_USER="root"
# MYSQL_ROOT_PASS="your_root_password_here"
```

When `wp.env` exists, the script loads it automatically and skips the prompts for those variables.

> **The database name is always prompted interactively**, regardless of `wp.env`. This is intentional — it prevents accidentally connecting to or overwriting an existing database.

## What the script does

| Step | Action |
|---|---|
| 1 | Creates `/var/www/<domain>` |
| 2 | Downloads and extracts the latest WordPress |
| 3 | Creates the MySQL/MariaDB database and user (optional) |
| 4 | Generates `wp-config.php` with unique auth keys and salts |
| 5 | Applies correct file system permissions (`www-data`) |
| 6 | Creates and enables the virtual host (Apache or Nginx) |

## Interactive prompts

### Section 1 — Site information
- **Domain** — e.g. `mydomain.com`. A leading `www.` is stripped automatically.

### Section 2 — Database
- **Database name** — always required. Only letters, numbers, and underscores are accepted (max 64 characters). The script aborts if a database with that name already exists.
- **Database user**, **password**, **host**, **table prefix** — skipped if set in `wp.env`.
- **Auto-create database** — if yes, MySQL/MariaDB root credentials are required (can also be set in `wp.env`).

### Section 3 — Web server
- Choose **Apache**, **Nginx**, or skip vhost configuration.
- Optionally add a `www.<domain>` alias.

### Section 4 — PHP version
- The script auto-detects installed PHP versions.
- You can pin a specific version (e.g. `8.2`) or use the system default.

## Virtual host notes

Both Apache and Nginx vhosts are created for **HTTP only (port 80)**. SSL/HTTPS configuration is not handled by this script and should be set up separately after installation.

- **Apache** vhost path: `/etc/apache2/sites-available/<domain>.conf`
- **Nginx** vhost path: `/etc/nginx/sites-available/<domain>.conf`

## After installation

1. Point the DNS `A` record of your domain to this server's IP.
2. Complete the WordPress setup wizard at: `http://<domain>/wp-admin/install.php`

## Security notes

- `wp-config.php` is created with permissions `640` (readable only by `www-data`).
- `DISALLOW_FILE_EDIT` is enabled — the theme/plugin file editor is disabled in wp-admin.
- `WP_DEBUG` is disabled by default.
- Auth keys and salts are fetched automatically from the official WordPress API.
- The script aborts if the target database already exists, preventing data corruption.
