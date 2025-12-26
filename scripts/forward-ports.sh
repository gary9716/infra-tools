#!/bin/bash

# Check if an argument was provided
if [ -z "$1" ]; then
  echo "Error: No target provided."
  echo "Usage: ./forward-ports.sh <local_port:remote_host:remote_port>"
  exit 1
fi

TARGET=$1
BASTION_HOST="zing-staging-bastion"

echo "Forwarding $TARGET through $BASTION_HOST..."
ssh -N -L "$TARGET" "$BASTION_HOST"