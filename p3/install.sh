#!/usr/bin/env bash

set -e

echo "🚀 Installing environment..."

CLUSTER_NAME="petit-nuage"
BOOSTRAP_MANIFEST_URL="https://raw.githubusercontent.com/Maxenceee/iot-42-cluster-conf/refs/heads/main/bootstrap.yml"

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
		debug "killing spinner ($SPINNER_PID)"
		kill "$SPINNER_PID"
	fi

	debug 'finished spinner'
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

install_argocd() {
	if kubectl get namespace argocd &> /dev/null; then
        echo "✅ ArgoCD est déjà installé (namespace trouvé)."
        return 0
    fi

    echo "📦 Installing ArgoCD..."
    
    # 1. Création du namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # 2. Installation via le manifest officiel
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    spinner_cmd "Waiting for ArgoCD components to be ready..." kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    # 3. Récupération du mot de passe admin (initial)
    ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo "---------------------------------------------------"
    echo "✅ ArgoCD est installé !"
    echo "👤 Utilisateur : admin"
    echo "🔑 Mot de passe : $ARGOCD_PWD"
    echo "---------------------------------------------------"
    echo "💡 Pour y accéder localement : kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

setup_argocd_bootstrap() {
	echo "🔄 Setting up ArgoCD bootstrap application..."

	kubectl apply -f $BOOSTRAP_MANIFEST_URL

	echo "✅ ArgoCD bootstrap application applied."
}

install_packages
install_docker
install_k3d
install_kubectl
install_argocd

echo "🔄 Creating K3d cluster..."

if k3d cluster list | grep -q "^$CLUSTER_NAME "; then
	echo "⚠️ K3d cluster '$CLUSTER_NAME' already exists. Skipping creation."
else
	k3d cluster create $CLUSTER_NAME --api-port 6443

	echo "✅ K3d cluster '$CLUSTER_NAME' created successfully."
fi

kubectl cluster-info --context "k3d-$CLUSTER_NAME"

kubectl get nodes

setup_argocd_bootstrap

echo "List of all pods, services, namespaces, and CRDs in the cluster:"

kubectl get pods,svc,ns,crd --all-namespaces

echo "✅ Environment setup complete!"