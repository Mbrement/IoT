#!/usr/bin/env bash

set -e

echo "🚀 Installing environment..."

CLUSTER_NAME="petit-nuage"

get_sudo() {
	SUDO=""

	if [[ $EUID -ne 0 ]]; then
		if command -v sudo &> /dev/null; then
			SUDO="sudo"
		else
			echo "⚠️ Not root and sudo not found. Trying to install without privileges..." >&2
		fi
	fi

	echo "$SUDO"
}

install_package() {
	local pkg=$1

	SUDO=$(get_sudo)

	if command -v apt &> /dev/null; then
		$SUDO apt update && $SUDO apt install -y "$pkg"
	else
		echo "❌ No supported package manager found. Install $pkg manually."
	fi
}

install_packages() {
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
}

install_docker() {
	if command -v docker &> /dev/null; then
		echo "✅ Docker is already installed."
		return 0
	fi

	echo "📦 Installing Docker..."

	SUDO=$(get_sudo)

	# Following Docker's official installation steps for Debian-based systems https://docs.docker.com/engine/install/debian/
	$SUDO install -m 0755 -d /etc/apt/keyrings
	$SUDO curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	$SUDO chmod a+r /etc/apt/keyrings/docker.asc
	$SUDO tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

	$SUDO apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
	$SUDO systemctl start docker
}

install_k3d() {
	if command -v k3d &> /dev/null; then
		echo "✅ k3d is already installed."
		return 0
	fi

	echo "📦 Installing k3d..."

	curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

install_kubectl() {
	if command -v kubectl &> /dev/null; then
		echo "✅ kubectl is already installed."
		return 0
	fi

	echo "📦 Installing kubectl..."

	SUDO=$(get_sudo)

	curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
	curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
	echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
	$SUDO install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

}

install_packages
install_docker
install_k3d
install_kubectl

echo "🔄 Creating K3d cluster..."

k3d cluster create $CLUSTER_NAME --api-port 6443

kubectl cluster-info --context "k3d-$CLUSTER_NAME"

kubectl get nodes

echo "✅ K3d cluster '$CLUSTER_NAME' created successfully."

echo "List of all pods, services, namespaces, and CRDs in the cluster:"

kubectl get pods,svc,ns,crd --all-namespaces

echo "✅ Environment setup complete!"