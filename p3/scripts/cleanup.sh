#!/usr/bin/env bash

echo "🧹 Cleaning up environment..."

if ! command -v k3d &> /dev/null; then
	echo "k3d not found, skipping cluster deletion."
	exit 0
fi

k3d cluster delete petit-nuage

echo "✅ Environment cleaned up!"