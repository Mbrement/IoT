#!/usr/bin/env bash

set -e

echo "🚀 Installing environment..."

install_package() {
	local pkg=$1
	local SUDO=""

	if [[ $EUID -ne 0 ]]; then
		if command -v sudo &> /dev/null; then
			SUDO="sudo"
		else
			echo "⚠️ Not root and sudo not found. Trying to install without privileges..."
		fi
	fi

	if command -v apt &> /dev/null; then
		$SUDO apt update && $SUDO apt install -y "$pkg"
	else
		echo "❌ No supported package manager found. Install $pkg manually."
	fi
}

install_docker() {
	if command -v docker &> /dev/null; then
		echo "✅ Docker is already installed."
		return 0
	fi

	# Following Docker's official installation steps for Debian-based systems https://docs.docker.com/engine/install/debian/
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc
	sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

	sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
	sudo systemctl start docker
}

install_k3d() {
	if command -v k3d &> /dev/null; then
		echo "✅ k3d is already installed."
		return 0
	fi

	curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

PREREQ_PKGS=(curl wget unzip ca-certificates)

MISSING_PKGS=()
for pkg in "${PREREQ_PKGS[@]}"; do
	if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
	echo "The following packages are required but missing: ${MISSING_PKGS[*]}"
	read -p "Do you want to install them now? (Y/n) " yn
	yn=${yn:-Y}
	if [[ "$yn" =~ ^[Yy]$ ]]; then
		for pkg in "${MISSING_PKGS[@]}"; do
			echo "📦 Installing $pkg..."
			install_package "$pkg"
		done
	else
		echo "⚠️ Some required packages are not installed. The script may not work correctly."
	fi
else
	echo "✅ All prerequisite packages are already installed."
fi

install_docker
install_k3d

echo "🔄 Creating K3d cluster..."

k3d cluster create mycluster

kubectl cluster-info --context k3d-mycluster

kubectl get nodes

echo "✅ Environment setup complete!"