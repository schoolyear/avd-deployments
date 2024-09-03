#!/bin/bash

set -e # so each commend gets printed as well

# Give the expected parameters a name
TRUSTED_PROXY_WHITELIST=$1        # comma seperated list of "<domain>:<port>", may include wildcards. For public internet facing proxy (trusted proxy)
SESSION_HOST_PROXY_WHITELIST=$2   # comma seperated list of "<domain>:<port>", may include wildcards. For session host facing proxy
TRUSTED_PROXY_TOKEN=$3            # trustedProxyToken, used for authentication against the API
API_BASE_URL=$4                   # base of Schoolyear API, without trailing slash
TRUSTED_PROXY_BINARY_URL=$5       # URL to download trusted proxy binary from
CERT_VAULT_NAME=$6                # name of the Key Vault that holds the HTTPS certificate for the trusted proxy
CERT_NAME=$7                      # name of the Certificate in that Key Vault

##################### SHARED #####################
# Download proxy binary
BINARY_PATH="/usr/local/share/syproxy"
echo "Downloading proxy binary"
curl -o $BINARY_PATH $TRUSTED_PROXY_BINARY_URL -s
chmod +x $BINARY_PATH
#####################/SHARED/#####################

##################### TRUSTED PROXY #####################
echo "Setting up Trusted proxy"
TRUSTED_PROXY_SERVICE_NAME="trustedproxy"
TRUSTED_PROXY_SERVICE_USER_NAME="sytrustedproxy"

echo "Creating service user for trusted proxy"
useradd -m $TRUSTED_PROXY_SERVICE_USER_NAME

TRUSTED_PROXY_BASE_PATH="/home/$TRUSTED_PROXY_SERVICE_USER_NAME"
TRUSTED_PROXY_WHITELIST_PATH="$TRUSTED_PROXY_BASE_PATH/whitelist.txt"
TRUSTED_PROXY_API_KEY_PATH="$TRUSTED_PROXY_BASE_PATH/api_key.txt"
TRUSTED_PROXY_PRIV_KEY_PATH="$TRUSTED_PROXY_BASE_PATH/private.pem"
TRUSTED_PROXY_CERT_PATH="$TRUSTED_PROXY_BASE_PATH/public.pem"

# Write whitelist
echo "Creating whitelist"
echo "$TRUSTED_PROXY_WHITELIST" > $TRUSTED_PROXY_WHITELIST_PATH

# Create key file
echo "Creating api key"
echo -n "$TRUSTED_PROXY_TOKEN" > $TRUSTED_PROXY_API_KEY_PATH

# Get Entra token
# python, since it is pre-installed on Ubuntu
echo "Request Entra token"
ACCESS_TOKEN=$(curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Get TLS certificate
# - fetch secret from API
# - extract field from JSON
# - base64 decode
# - extract private key from secret (tee, because we need to write two separate files)
# - generate public key from secret
echo "Getting TLS certificate"
curl -H "Authorization: Bearer $ACCESS_TOKEN" "https://$CERT_VAULT_NAME.vault.azure.net/secrets/$CERT_NAME?api-version=7.4" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['value'])" \
  | openssl base64 -d -A \
  | tee >(openssl pkcs12 -passin pass: -nodes -nocerts -out $TRUSTED_PROXY_PRIV_KEY_PATH) \
  | openssl pkcs12 -passin pass: -nokeys -out $TRUSTED_PROXY_CERT_PATH


# Grant service user access to files
# because this script is writing the files as owned by root
echo "Granting service user access to files"
chown $TRUSTED_PROXY_SERVICE_USER_NAME:$TRUSTED_PROXY_SERVICE_USER_NAME -R $TRUSTED_PROXY_BASE_PATH

# Install trusted proxy service
# CAP_NET_BIND_SERVICE is required to start on a protected port without elevated privileges
echo "Installing trusted proxy service"
echo "[Unit]
Description=$TRUSTED_PROXY_SERVICE_NAME
After=network.target

[Service]
User=$TRUSTED_PROXY_SERVICE_USER_NAME
ExecStart=$BINARY_PATH -api-key $TRUSTED_PROXY_API_KEY_PATH -host-whitelist $TRUSTED_PROXY_WHITELIST_PATH -tls-cert $TRUSTED_PROXY_CERT_PATH -tls-key $TRUSTED_PROXY_PRIV_KEY_PATH -listen-address :443 -ulimit 0 -api-base-url $API_BASE_URL
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=default.target" > /etc/systemd/system/$TRUSTED_PROXY_SERVICE_NAME.service

echo "Starting trusted proxy service"
systemctl daemon-reload
systemctl enable $TRUSTED_PROXY_SERVICE_NAME.service
systemctl start $TRUSTED_PROXY_SERVICE_NAME.service

echo "Setting up Trusted proxy: DONE"
#####################/TRUSTED PROXY/#####################


##################### SESSION HOST PROXY #####################
echo "Setting up Session Host proxy"

SESSION_HOST_PROXY_SERVICE_NAME="sessionhostproxy"
SESSION_HOST_PROXY_SERVICE_USER_NAME="sysessionhostproxy"

echo "Creating service user for session host proxy"
useradd -m $SESSION_HOST_PROXY_SERVICE_USER_NAME

SESSION_HOST_PROXY_BASE_PATH="/home/$SESSION_HOST_PROXY_SERVICE_USER_NAME"
SESSION_HOST_PROXY_WHITELIST_PATH="$SESSION_HOST_PROXY_BASE_PATH/whitelist.txt"

# Write whitelist
echo "Creating whitelist"
echo "$SESSION_HOST_PROXY_WHITELIST" > $SESSION_HOST_PROXY_WHITELIST_PATH

# Grant service user access to files
# because this script is writing the files as owned by root
echo "Granting service user access to files"
chown $SESSION_HOST_PROXY_SERVICE_USER_NAME:$SESSION_HOST_PROXY_SERVICE_USER_NAME -R $SESSION_HOST_PROXY_BASE_PATH

echo "Installing session host proxy service"
echo "[Unit]
Description=$SESSION_HOST_PROXY_SERVICE_NAME
After=network.target

[Service]
User=$SESSION_HOST_PROXY_SERVICE_USER_NAME
ExecStart=$BINARY_PATH -simple-proxy-mode -host-whitelist $SESSION_HOST_PROXY_WHITELIST_PATH

[Install]
WantedBy=default.target" > /etc/systemd/system/$SESSION_HOST_PROXY_SERVICE_NAME.service

echo "Starting session host proxy service"
systemctl daemon-reload
systemctl enable $SESSION_HOST_PROXY_SERVICE_NAME.service
systemctl start $SESSION_HOST_PROXY_SERVICE_NAME.service

echo "Setting up Session Host proxy: DONE"
#####################/SESSION HOST PROXY/#####################

echo "Proxy installation completed"