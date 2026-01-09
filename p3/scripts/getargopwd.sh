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

KUBECMD="$(get_sudo) kubectl"

ARGOCD_PWD=$($KUBECMD -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
	
echo "---------------------------------------------------"
echo "✅ ArgoCD is installed!"
echo "👤 User: admin"
echo "🔑 Password: $ARGOCD_PWD"
echo "---------------------------------------------------"
echo "💡 To access it locally: kubectl port-forward svc/argocd-server -n argocd 8000:443"