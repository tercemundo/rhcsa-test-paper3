#!/bin/bash
set -euo pipefail

# ====== CONFIG ======
# INSTALL_GUI=1 instala "Server with GUI" en servera/serverb (pesado, por defecto NO)
# REBOOT=1 reinicia servera/serverb al terminar (por defecto NO)
unset REPO_URL
REPO_URL="https://github.com/codexchangee/rhcsa-test-paper3.git"

BRANCH="${BRANCH:-main}"
HTML_DIR="/var/www/html"

# Remote hosts (change if needed)
SERVERA_HOST="${SERVERA_HOST:-servera}"
SERVERB_HOST="${SERVERB_HOST:-serverb}"
SERVER_SSH_USER="${SERVER_SSH_USER:-root}"

# ====== Helpers ======
pkg_mgr() {
  if command -v dnf >/dev/null 2>&1; then
    echo dnf
  else
    echo yum
  fi
}

need_pkg() {
  local pkg="$1"
  if ! rpm -q "$pkg" >/dev/null 2>&1; then
    $PKG -y install "$pkg"
  fi
}

safe_systemctl_enable_now() {
  local svc="$1"
  systemctl enable --now "$svc" 2>/dev/null || systemctl enable "$svc" || true
  systemctl start "$svc" 2>/dev/null || true
}

# ====== Start ======
PKG="$(pkg_mgr)"

echo "[1/7] Installing required packages..."
need_pkg git
need_pkg httpd
need_pkg nfs-utils
need_pkg firewalld || true

echo "[2/7] (Optional) Ensure firewalld is running..."
safe_systemctl_enable_now firewalld || true

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Si el repo local (con html/, servera.sh y serverb.sh) esta presente, se usa ESE.
# Asi se ejecutan tus scripts corregidos y no los del repo original de GitHub.
if [ -d "$SCRIPT_DIR/html" ] && [ -f "$SCRIPT_DIR/servera.sh" ] && [ -f "$SCRIPT_DIR/serverb.sh" ]; then
  echo "[3/7] Usando archivos locales de $SCRIPT_DIR (sin clonar)"
  SRC="$SCRIPT_DIR"
else
  echo "[3/7] Cloning repo: $REPO_URL (branch: $BRANCH)"
  if git ls-remote "$REPO_URL" &>/dev/null; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR/repo"
  else
    echo "ERROR: Repo is private or unreachable: $REPO_URL"
    exit 1
  fi
  SRC="$WORKDIR/repo"
fi

echo "[4/7] Deploying HTML to $HTML_DIR..."
mkdir -p "$HTML_DIR"
# Copy html/ folder contents if present; otherwise copy *.html from repo root
if [ -d "$SRC/html" ]; then
  find "$SRC/html" -type f -name "*.html" -exec cp -f {} "$HTML_DIR"/ \;
else
  echo "No html/ directory found; checking for root-level *.html files..."
  find "$SRC" -maxdepth 1 -type f -name "*.html" -exec cp -f {} "$HTML_DIR"/ \; || true
fi

# Ensure index.html exists
if [ ! -f "$HTML_DIR/index.html" ]; then
  cat > "$HTML_DIR/index.html" <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>Site</title></head>
<body>
<h1>Site Deployed</h1>
<p>No index.html was present in the repo, so this placeholder was created.</p>
</body></html>
EOF
fi

# Optional: set ownership for Apache
if id apache &>/dev/null; then
  chown -R apache:apache "$HTML_DIR"
fi

echo "[5/7] Enabling and starting httpd..."
safe_systemctl_enable_now httpd

echo "[6/7] NFS server configuration (as in your earlier script)..."
safe_systemctl_enable_now rpcbind
safe_systemctl_enable_now nfs-server

# Temporarily set SELinux permissive if command exists (optional, mirrors your script)
if command -v setenforce >/dev/null 2>&1; then
  setenforce 0 || true
fi

# Open firewall for NFS (ignore if firewalld isn’t present)
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=nfs || true
  firewall-cmd --permanent --add-service=mountd || true
  firewall-cmd --permanent --add-service=rpc-bind || true
  firewall-cmd --reload || true
fi

mkdir -p /ourhome/remoteuser3
chmod 777 /ourhome/remoteuser3

# Avoid duplicate export line
grep -qE '^[[:space:]]*/ourhome/remoteuser3[[:space:]]' /etc/exports \
  || echo "/ourhome/remoteuser3 *(rw,sync)" >> /etc/exports

exportfs -rv || true
systemctl restart nfs-server || true
systemctl restart rpcbind || true

echo "[7/7] Running server scripts on servera and serverb over SSH..."

# Ensure scripts exist in repo
if [ ! -f "$SRC/servera.sh" ] || [ ! -f "$SRC/serverb.sh" ]; then
  echo "ERROR: servera.sh and/or serverb.sh not found in the repo root."
  echo "Place them at: rhcsa-papers/servera.sh and rhcsa-papers/serverb.sh"
  exit 1
fi

# Make sure they are executable locally (optional)
chmod +x "$SRC/servera.sh" "$SRC/serverb.sh" || true

run_remote() {
  local host="$1"
  local script_path="$2"
  echo "==> Executing $(basename "$script_path") on $host..."
  # Copy and run atomically so host keeps a copy
  scp -q -o StrictHostKeyChecking=no "$script_path" "${SERVER_SSH_USER}@${host}:/root/remote_run.sh"
  ssh -o StrictHostKeyChecking=no "${SERVER_SSH_USER}@${host}" "chmod +x /root/remote_run.sh && INSTALL_GUI=${INSTALL_GUI:-0} REBOOT=${REBOOT:-0} /root/remote_run.sh"
}

# Execute
run_remote "$SERVERA_HOST" "$SRC/servera.sh"
run_remote "$SERVERB_HOST" "$SRC/serverb.sh"


echo "All done"
