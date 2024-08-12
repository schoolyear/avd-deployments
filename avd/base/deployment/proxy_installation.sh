#!/bin/bash

set -e

# $1: whitelist
# $2: trustedProxyToken
# $3: vault name
# $4: certificate name
# $5: api base URL

SERVICE_NAME="syproxy"
USER_NAME="syproxy"

PROXY_SHA256="f2ac91bbcb73ae7fd06fddf5213485af40aebfb2cce85ce0256bf09238413859"
PROXY_URL="https://schoolyear-email-assets.s3.eu-west-1.amazonaws.com/proxy"

# Create User with home directory
echo "Creating service user"
useradd -m $USER_NAME

BASE_PATH="/home/$USER_NAME"
BINARY_PATH="$BASE_PATH/proxy"
WHITELIST_PATH="$BASE_PATH/whitelist.txt"
API_KEY_PATH="$BASE_PATH/api_key.txt"
PRIV_KEY_PATH="$BASE_PATH/private.pem"
CERT_PATH="$BASE_PATH/public.pem"

# Download proxy binary
echo "Downloading proxy binary"
curl -o $BINARY_PATH $PROXY_URL -s && echo "$PROXY_SHA256 $BINARY_PATH" | sha256sum -c
chmod +x $BINARY_PATH

# Create Whitelist
echo "Creating whitelist"
echo "$1" > $WHITELIST_PATH

# Create key file
echo "Creating api key"
echo -n "$2" > $API_KEY_PATH

# Get Entra token
echo "Request Entra token"
ACCESS_TOKEN=$(curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Get TLS certificate
echo "Getting TLS certificate"
curl -H "Authorization: Bearer $ACCESS_TOKEN" "https://$3.vault.azure.net/secrets/$4?api-version=7.4" | python3 -c "import sys, json; print(json.load(sys.stdin)['value'])" | openssl base64 -d -A | tee >(openssl pkcs12 -passin pass: -nodes -nocerts -out $PRIV_KEY_PATH) | openssl pkcs12 -passin pass: -nokeys -out $CERT_PATH

# Grant user access to files
echo "Granting service user access to files"
chown $USER_NAME:$USER_NAME -R $BASE_PATH

# Install service
echo "Installing service"
echo "[Unit]
Description=$SERVICE_NAME
After=network.target

[Service]
User=$USER_NAME
ExecStart=$BINARY_PATH -api-key $API_KEY_PATH -host-whitelist $WHITELIST_PATH -tls-cert $CERT_PATH -tls-key $PRIV_KEY_PATH -listen-address :443 -ulimit 0 -api-base-url $5
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=default.target" > /etc/systemd/system/$SERVICE_NAME.service

systemctl daemon-reload
systemctl enable $SERVICE_NAME.service
systemctl start $SERVICE_NAME.service

###  Simple proxy install for office whitelisting ###
# todo: change to trusted-proxy
# todo: add api base to trusted-proxy

# Variables
S3_URL="https://schoolyear-email-assets.s3.eu-west-1.amazonaws.com/simple-proxy"
PROXY_CONFIG_S3_URL="https://schoolyear-email-assets.s3.eu-west-1.amazonaws.com/whitelist.conf"
EXECUTABLE="/usr/local/bin/simple-proxy"
SIMPLE_PROXY_CONFIG_FOLDER="/etc/simple-proxy"
WHITELIST_CONF="/etc/simple-proxy/whitelist.conf"
SERVICE_NAME="simple-proxy.service"

echo "Creating $SIMPLE_PROXY_CONFIG_FOLDER..."
mkdir $SIMPLE_PROXY_CONFIG_FOLDER

# Download the executable
echo "Downloading simple-proxy..."
curl -o $EXECUTABLE $S3_URL

# Downloading the whitelist.conf file
echo "Downloading whitelist.conf"
curl -o $WHITELIST_CONF $PROXY_CONFIG_S3_URL

# Make sure the executable can be run
echo "Setting executable permissions..."
chmod +x $EXECUTABLE

# Create the systemd service file
echo "Creating systemd service..."
cat <<EOL > /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Simple Proxy Service
After=network.target

[Service]
ExecStart=$EXECUTABLE -config /etc/simple-proxy/whitelist.conf
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd to pick up the new service
echo "Reloading systemd..."
systemctl daemon-reload

# Enable and start the service
echo "Enabling and starting simple-proxy service..."
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
systemctl status $SERVICE_NAME

echo "Setup complete. The simple-proxy service is now running."

### /Simple proxy install for office whitelisting ###

echo "DONE"