#!/usr/bin/env bash

set -e

source "./scripts/tests/lib.sh"

client_curl_resource

docker compose stop api # Stop portal

sleep 5 # Wait for client to disconnect

client_curl_resource