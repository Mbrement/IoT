#!/usr/bin/env bash
#
# This script sets up a local Kubernetes environment using k3d,
# installs necessary tools, and deploys ArgoCD with a bootstrap application.
# It is not production-ready and is intended for educational purposes only.
#
# You should not run this script on your host machine directly.
# Instead, run it inside the provided VM or containerized environment.

set -e

echo "🚀 Installing environment..."

CLUSTER_NAME="petit-nuage"
# URL of the ArgoCD bootstrap manifest
BOOSTRAP_MANIFEST_URL="https://raw.githubusercontent.com/Maxenceee/iot-42-cluster-conf/refs/heads/main/bootstrap.yml"
# List of all port mappings for the k3d cluster
# K3d runs on Docker, it cannot automatically map ports based on services like a normal Kubernetes cluster.
PORT_MAPPING=(
	"8888:30088"
)

#### Spinner functions and utility functions ####

SPINNER_PID=
CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

spinner() {
	local c
	local message=$1
	while true; do
		for c in "${CHARS[@]}"; do
			printf ' %s \r' "$c $message"
			sleep .1
		done
	done
}

cleanup() {
	if [[ -n $SPINNER_PID ]]; then
		kill "$SPINNER_PID"
	fi
}

spinner_cmd() {
	local message=$1
	shift
	trap cleanup EXIT
	spinner "$message" &
	SPINNER_PID=$!

	"$@"

	cleanup
	trap - EXIT
}

#### Installation functions ####

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
		echo "❌ No supported package manager found. Install $pkg manually." >&2
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
			echo "⚠️ Some required packages are not installed. The script may not work correctly." >&2
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

	if [ -f /etc/os-release ]; then
        . /etc/os-release
    else
        echo "❌ Error: Cannot detect OS (missing /etc/os-release)." >&2
        exit 1
    fi

    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        echo "❌ Error: This script only supports Debian or Ubuntu. (Detected: $ID)" >&2
        exit 1
    fi

	echo "📦 Installing Docker for $ID ($VERSION_CODENAME)..."

	SUDO=$(get_sudo)

	# Following Docker's official installation https://docs.docker.com/engine/install
	$SUDO install -m 0755 -d /etc/apt/keyrings

	local GPG_URL="https://download.docker.com/linux/$ID/gpg"

	$SUDO curl -fsSL "$GPG_URL" -o /etc/apt/keyrings/docker.asc
	$SUDO chmod a+r /etc/apt/keyrings/docker.asc

	$SUDO tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$ID
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

	$SUDO apt update
	$SUDO apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
	$SUDO systemctl start docker

	echo "🔄 Adding $USER to docker group..."
	$SUDO usermod -aG docker $USER
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

setup_cluster() {
	echo "🔄 Creating K3d cluster..."

	SUDO=$(get_sudo)

	if $SUDO k3d cluster list | grep -q "^$CLUSTER_NAME "; then
		echo "⚠️ K3d cluster '$CLUSTER_NAME' already exists. Skipping creation."
	else
		K3D_PORTS=()
		for mapping in "${PORT_MAPPING[@]}"; do
			K3D_PORTS+=("-p" "${mapping}@server:0")
		done

		$SUDO k3d cluster create "$CLUSTER_NAME" \
			--api-port 6443 \
			"${K3D_PORTS[@]}" \
			--wait

		echo "✅ K3d cluster '$CLUSTER_NAME' created successfully."
	fi
}

install_argocd() {
	if $KUBECMD get namespace argocd &> /dev/null; then
		echo "✅ ArgoCD is already installed (namespace found)."
		return 0
	fi

	echo "📦 Installing ArgoCD..."

	$KUBECMD create namespace argocd --dry-run=client -o yaml | $KUBECMD apply -f -
	$KUBECMD apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

	spinner_cmd "Waiting for ArgoCD components to be ready..." $KUBECMD wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

	ARGOCD_PWD=$($KUBECMD -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
	
	echo "---------------------------------------------------"
	echo "✅ ArgoCD is installed!"
	echo "👤 User: admin"
	echo "🔑 Password: $ARGOCD_PWD"
	echo "---------------------------------------------------"
	echo "💡 To access it locally: kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

setup_argocd_bootstrap() {
	echo "🔄 Setting up ArgoCD bootstrap application..."

	$KUBECMD apply -f $BOOSTRAP_MANIFEST_URL

	echo "✅ ArgoCD bootstrap application applied."
}

install_packages
install_docker
install_k3d
install_kubectl

setup_cluster

echo "🔄 Configuring kubectl context..."

KUBECMD="$(get_sudo) kubectl"

$KUBECMD cluster-info --context "k3d-$CLUSTER_NAME"

$KUBECMD get nodes

install_argocd
setup_argocd_bootstrap

echo "List of all pods, services, namespaces, and CRDs in the cluster:"

$KUBECMD get pods,svc,ns,crd --all-namespaces

echo "✅ Environment setup complete!"
echo "💡 You may need to login again to access to the new environment."
