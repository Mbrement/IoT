#!/usr/bin/env bash

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

echo "🧹 Cleaning up environment..."

clean_k3d() {
	if ! command -v k3d &> /dev/null; then
		echo "k3d not found, skipping cluster deletion."
		exit 0
	fi

	SUDO=$(get_sudo)

	if k3d cluster list | grep -q "petit-nuage"; then
		echo "Stopping and deleting cluster 'petit-nuage'..."
		$SUDO k3d cluster delete petit-nuage
	fi

	echo "Removing unused docker volumes..."
	docker volume prune -f

	if [ -f /usr/local/bin/k3d ]; then
        echo "Removing k3d binary..."
        $SUDO rm /usr/local/bin/k3d
    fi

	if [ -d "$HOME/.k3d" ]; then
        echo "Removing local k3d config directory..."
        rm -rf "$HOME/.k3d"
    fi

    echo "✨ k3d cleanup complete!"
}

clean_kubectl() {
    echo "🗑️  Cleaning up kubectl..."
    SUDO=$(get_sudo)

    if [ -f /usr/local/bin/kubectl ]; then
        echo "Removing kubectl binary..."
        $SUDO rm /usr/local/bin/kubectl
    fi

    if [ -d "$HOME/.kube" ]; then
        echo "Removing $HOME/.kube directory..."
        rm -rf "$HOME/.kube"
    fi

    if [ -d "$HOME/.cache/kubectl" ]; then
        rm -rf "$HOME/.cache/kubectl"
    fi

    echo "✨ kubectl cleanup complete!"
}

clean_docker() {
	echo "🗑️  Uninstalling Docker and cleaning up all data..."
    SUDO=$(get_sudo)

    $SUDO systemctl stop docker.socket || true
    $SUDO systemctl stop docker || true

    $SUDO apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

    $SUDO apt-get autoremove -y
    $SUDO apt-get autoclean

    echo "Purging Docker directories (/var/lib/docker, /etc/docker)..."
    $SUDO rm -rf /var/lib/docker
    $SUDO rm -rf /var/lib/containerd
    $SUDO rm -rf /etc/docker

    if getent group docker > /dev/null; then
        $SUDO groupdel docker
    fi

    $SUDO rm -f /etc/apt/keyrings/docker.asc
    $SUDO rm -f /etc/apt/sources.list.d/docker.sources

    echo "✨ Docker has been completely removed."
}

clean_k3d
clean_kubectl
clean_docker

echo "✅ Environment cleaned up!"