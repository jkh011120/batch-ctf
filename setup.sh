#!/bin/bash
set -e

echo "========================================="
echo "  batch-ctf Environment Setup Script"
echo "========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; }

# Check root
if [ "$EUID" -eq 0 ]; then
    error "Do not run as root. The script will use sudo when needed."
    exit 1
fi

###############################################################################
# 1. System packages (apt)
###############################################################################
log "Updating apt cache..."
sudo apt update -y

log "Installing system packages..."
sudo apt install -y \
    python3 python3-pip python3-venv python3-dev \
    binutils file patchelf gdb \
    ruby ruby-dev \
    strace ltrace \
    upx-ucl \
    curl wget jq \
    tshark wireshark-common \
    libimage-exiftool-perl binwalk steghide \
    sleuthkit foremost \
    sox libsox-fmt-all \
    zbar-tools \
    openjdk-17-jdk unzip \
    build-essential libssl-dev libffi-dev \
    netcat-openbsd nmap \
    git

# Docker — only install if not already present
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    sudo apt install -y docker.io 2>/dev/null || warn "Docker install failed. Install manually."
else
    warn "Docker already installed ($(docker --version)), skipping."
fi

###############################################################################
# 2. Docker group
###############################################################################
if ! groups "$USER" | grep -q docker; then
    log "Adding $USER to docker group..."
    sudo usermod -aG docker "$USER"
    warn "Docker group added. You may need to log out and back in."
fi

###############################################################################
# 3. Python packages (pip)
###############################################################################
log "Installing Python packages..."
pip install --break-system-packages 2>/dev/null || true
pip install \
    pwntools \
    z3-solver \
    ROPgadget \
    pycryptodome \
    gmpy2 \
    sympy \
    volatility3 \
    uncompyle6 \
    ropper \
    capstone \
    unicorn \
    keystone-engine \
    angr \
    requests \
    beautifulsoup4 \
    2>/dev/null || \
pip install --break-system-packages \
    pwntools \
    z3-solver \
    ROPgadget \
    pycryptodome \
    gmpy2 \
    sympy \
    volatility3 \
    uncompyle6 \
    ropper \
    capstone \
    unicorn \
    keystone-engine \
    angr \
    requests \
    beautifulsoup4

###############################################################################
# 4. Ruby gems
###############################################################################
log "Installing Ruby gems..."
sudo gem install one_gadget
sudo gem install zsteg

###############################################################################
# 5. pwndbg (GDB plugin)
###############################################################################
if [ ! -d "$HOME/pwndbg" ]; then
    log "Installing pwndbg..."
    git clone https://github.com/pwndbg/pwndbg "$HOME/pwndbg"
    cd "$HOME/pwndbg" && ./setup.sh
    cd -
else
    warn "pwndbg already installed, skipping."
fi

###############################################################################
# 6. Ghidra
###############################################################################
GHIDRA_VERSION="11.3.1"
GHIDRA_DATE="20250219"
GHIDRA_DIR="/opt/ghidra"

if [ ! -d "$GHIDRA_DIR" ]; then
    log "Installing Ghidra ${GHIDRA_VERSION}..."
    GHIDRA_ZIP="ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip"
    GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/${GHIDRA_ZIP}"

    wget -q --show-progress -O "/tmp/${GHIDRA_ZIP}" "$GHIDRA_URL" || {
        warn "Ghidra download failed. Install manually from https://ghidra-sre.org/"
    }

    if [ -f "/tmp/${GHIDRA_ZIP}" ]; then
        sudo unzip -q "/tmp/${GHIDRA_ZIP}" -d /opt/
        sudo mv /opt/ghidra_${GHIDRA_VERSION}_PUBLIC "$GHIDRA_DIR"
        sudo ln -sf "$GHIDRA_DIR/ghidraRun" /usr/local/bin/ghidra
        sudo ln -sf "$GHIDRA_DIR/support/analyzeHeadless" /usr/local/bin/analyzeHeadless
        rm "/tmp/${GHIDRA_ZIP}"
        log "Ghidra installed at ${GHIDRA_DIR}"
    fi
else
    warn "Ghidra already installed at ${GHIDRA_DIR}, skipping."
fi

###############################################################################
# 7. ffuf (directory fuzzer)
###############################################################################
if ! command -v ffuf &>/dev/null; then
    log "Installing ffuf..."
    FFUF_URL="https://github.com/ffuf/ffuf/releases/latest/download/ffuf_2.1.0_linux_amd64.tar.gz"
    wget -q --show-progress -O /tmp/ffuf.tar.gz "$FFUF_URL" || {
        warn "ffuf download failed. Install manually."
    }
    if [ -f /tmp/ffuf.tar.gz ]; then
        tar xzf /tmp/ffuf.tar.gz -C /tmp/ ffuf
        sudo mv /tmp/ffuf /usr/local/bin/
        rm /tmp/ffuf.tar.gz
        log "ffuf installed."
    fi
else
    warn "ffuf already installed, skipping."
fi

###############################################################################
# 8. gobuster
###############################################################################
if ! command -v gobuster &>/dev/null; then
    log "Installing gobuster..."
    sudo apt install -y gobuster 2>/dev/null || {
        warn "gobuster not in apt. Install manually or use ffuf instead."
    }
else
    warn "gobuster already installed, skipping."
fi

###############################################################################
# 9. SageMath (optional, large)
###############################################################################
read -p "Install SageMath? (large download, ~2GB) [y/N]: " INSTALL_SAGE
if [[ "$INSTALL_SAGE" =~ ^[Yy]$ ]]; then
    log "Installing SageMath..."
    sudo apt install -y sagemath
else
    warn "Skipping SageMath. Install later with: sudo apt install sagemath"
fi

###############################################################################
# 10. Wordlists
###############################################################################
if [ ! -d "/usr/share/wordlists" ]; then
    log "Installing SecLists wordlists..."
    sudo mkdir -p /usr/share/wordlists
    sudo apt install -y seclists 2>/dev/null || {
        warn "seclists not in apt. Downloading common wordlist..."
        sudo wget -q -O /usr/share/wordlists/common.txt \
            "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt"
    }
else
    warn "Wordlists already exist, skipping."
fi

###############################################################################
# 11. checksec (standalone if not bundled with pwntools)
###############################################################################
if ! command -v checksec &>/dev/null; then
    log "Installing checksec..."
    sudo apt install -y checksec 2>/dev/null || {
        wget -q -O /tmp/checksec https://raw.githubusercontent.com/slimm609/checksec.sh/master/checksec
        chmod +x /tmp/checksec
        sudo mv /tmp/checksec /usr/local/bin/
    }
else
    warn "checksec already installed, skipping."
fi

###############################################################################
# Done
###############################################################################
echo ""
echo "========================================="
log "Setup complete!"
echo "========================================="
echo ""
echo "Installed:"
echo "  - Python3 + pwntools, z3, ROPgadget, angr, volatility3, etc."
echo "  - GDB + pwndbg"
echo "  - Ghidra (headless: analyzeHeadless)"
echo "  - Ruby + one_gadget, zsteg"
echo "  - ffuf, tshark, binwalk, steghide, exiftool"
echo "  - sleuthkit, foremost, sox, zbar-tools"
echo ""
warn "Remember to log out and back in if Docker group was added."
warn "Set GHIDRA_HOME=/opt/ghidra if needed."
