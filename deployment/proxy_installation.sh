#!/bin/bash

# WARNING: make sure this script can run idempotent (aka can be ran multiple times on the same machine)

set -e # so each commend gets printed as well

##################### PARAMETERS #####################
# Give the expected parameters a name
TRUSTED_PROXY_WHITELIST=$1        # comma seperated list of "<domain>:<port>", may include wildcards. For public internet facing proxy (trusted proxy)
SESSION_HOST_PROXY_WHITELIST=$2   # comma seperated list of "<domain>:<port>", may include wildcards. For session host facing proxy
TRUSTED_PROXY_TOKEN=$3            # trustedProxyToken, used for authentication against the API
API_BASE_URL=$4                   # base of Schoolyear API, without trailing slash
TRUSTED_PROXY_BINARY_URL=$5       # URL to download trusted proxy binary from
CERT_VAULT_NAME=$6                # name of the Key Vault that holds the HTTPS certificate for the trusted proxy
CERT_NAME=$7                      # name of the Certificate in that Key Vault
AUTH_BYPASS_NETS=$8               # comma separate list of CIDRs that bypass the proxy auth of the trusted proxy, used for Chromebook deployments
#####################/PARAMETERS/#####################

##################### SHARED #####################
# Download proxy binary
# Download to a temporary location first, then move, so we can do this while the binary is already running
BINARY_PATH="/usr/local/share/syproxy"
BINARY_PATH_NEXT="$BINARY_PATH-next"

echo "Downloading proxy binary"
PROXY_DOWNLOAD_STATUS=$(curl -s -w "%{http_code}" -o $BINARY_PATH_NEXT $TRUSTED_PROXY_BINARY_URL) || {
    echo "Curl failed to download the trusted proxy with exit code $? (see https://everything.curl.dev/cmdline/exitcode.html): $TRUSTED_PROXY_BINARY_URL"
    exit 49
}

if [ "$PROXY_DOWNLOAD_STATUS" -ne 200 ]; then
    echo "HTTP error when downloading proxy binary: $PROXY_DOWNLOAD_STATUS ($TRUSTED_PROXY_BINARY_URL)"
    exit 50
fi

chmod +x $BINARY_PATH_NEXT
mv $BINARY_PATH_NEXT $BINARY_PATH
#####################/SHARED/#####################


##################### TRUSTED PROXY #####################
echo "Setting up Trusted proxy"
TRUSTED_PROXY_SERVICE_NAME="trustedproxy"
TRUSTED_PROXY_SERVICE_USER_NAME="sytrustedproxy"

echo "Creating service user for trusted proxy"
id -u $TRUSTED_PROXY_SERVICE_USER_NAME &>/dev/null || useradd -m $TRUSTED_PROXY_SERVICE_USER_NAME

TRUSTED_PROXY_BASE_PATH="/home/$TRUSTED_PROXY_SERVICE_USER_NAME"
TRUSTED_PROXY_WHITELIST_PATH="$TRUSTED_PROXY_BASE_PATH/whitelist.txt"
TRUSTED_PROXY_API_KEY_PATH="$TRUSTED_PROXY_BASE_PATH/api_key.txt"
TRUSTED_PROXY_AUTH_BYPASS_PATH="$TRUSTED_PROXY_BASE_PATH/auth_bypass.txt"
TRUSTED_PROXY_PRIV_KEY_PATH="$TRUSTED_PROXY_BASE_PATH/private.pem"
TRUSTED_PROXY_CERT_PATH="$TRUSTED_PROXY_BASE_PATH/public.pem"

# Write whitelist
echo "Creating whitelist"
echo "$TRUSTED_PROXY_WHITELIST" > $TRUSTED_PROXY_WHITELIST_PATH

# Create key file
echo "Creating api key"
echo -n "$TRUSTED_PROXY_TOKEN" > $TRUSTED_PROXY_API_KEY_PATH

# Create auth bypass file
echo "Creating auth-bypass file"
echo -n "$AUTH_BYPASS_NETS" > $TRUSTED_PROXY_AUTH_BYPASS_PATH

# Get Entra token
# this uses python because it is pre-installed on Ubuntu
echo "Request Entra token"
ENTRA_URL="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"

MAX_RETRIES=5
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
  ENTRA_RESPONSE=$(curl -s -o - -w "%{http_code}" -H "Metadata: true" $ENTRA_URL) || {
      echo "Curl failed to fetch entra access_token with exit code $? (see https://everything.curl.dev/cmdline/exitcode.html): $ENTRA_URL"
      exit 49
  }
  ENTRA_STATUS="${ENTRA_RESPONSE: -3}"
  ENTRA_BODY="${ENTRA_RESPONSE:0:${#ENTRA_RESPONSE}-3}"

  if [ "$ENTRA_STATUS" -eq 200 ]; then
    break
  fi

  echo "request failed with ($ENTRA_STATUS): $ENTRA_BODY"
  echo "retrying..."
  COUNT=$((COUNT+1))
  sleep 10
done

if [ "$ENTRA_STATUS" -ne 200 ]; then
  echo "Failed with status code $ENTRA_STATUS"
  echo "Response body:"
  echo "$ENTRA_BODY"
  exit 51
fi

echo "Parsing access_token from Entra token response"
ACCESS_TOKEN=$(echo $ENTRA_BODY | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Get TLS certificate
KEYVAULT_URL="https://$CERT_VAULT_NAME.vault.azure.net/secrets/$CERT_NAME?api-version=7.4"
CERT_RESPONSE=$(curl -s -o - -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" $KEYVAULT_URL) || {
    echo "Curl failed to fetch TLS certificate from keyvault with exit code $? (see https://everything.curl.dev/cmdline/exitcode.html): $KEYVAULT_URL"
    exit 49
}
CERT_STATUS="${CERT_RESPONSE: -3}"
CERT_BODY="${CERT_RESPONSE:0:${#CERT_RESPONSE}-3}"

if [ "$CERT_STATUS" -ne 200 ]; then
  echo "Failed with status code $CERT_STATUS"
  echo "Response body:"
  echo "$CERT_BODY"
  exit 52
fi

# - extract field from JSON
# - base64 decode
# - extract private key from secret (tee, because we need to write two separate files)
# - generate public key from secret
echo "Parsing TLS certificate response"
echo "$CERT_BODY" \
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
ExecStart=$BINARY_PATH -api-key $TRUSTED_PROXY_API_KEY_PATH -host-whitelist $TRUSTED_PROXY_WHITELIST_PATH -tls-cert $TRUSTED_PROXY_CERT_PATH -tls-key $TRUSTED_PROXY_PRIV_KEY_PATH -listen-address :443 -api-base-url $API_BASE_URL -auth-bypass $TRUSTED_PROXY_AUTH_BYPASS_PATH
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=default.target" > /etc/systemd/system/$TRUSTED_PROXY_SERVICE_NAME.service

echo "Starting trusted proxy service"
systemctl daemon-reload
systemctl enable $TRUSTED_PROXY_SERVICE_NAME.service
systemctl restart $TRUSTED_PROXY_SERVICE_NAME.service # restart: idempotency

echo "Setting up Trusted proxy: DONE"
#####################/TRUSTED PROXY/#####################


##################### SESSION HOST PROXY #####################
echo "Setting up Session Host proxy"

SESSION_HOST_PROXY_SERVICE_NAME="sessionhostproxy"
SESSION_HOST_PROXY_SERVICE_USER_NAME="sysessionhostproxy"

echo "Creating service user for session host proxy"
id -u $SESSION_HOST_PROXY_SERVICE_USER_NAME &>/dev/null || useradd -m $SESSION_HOST_PROXY_SERVICE_USER_NAME

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
ExecStart=$BINARY_PATH -simple-proxy-mode -host-whitelist $SESSION_HOST_PROXY_WHITELIST_PATH -host-pac

[Install]
WantedBy=default.target" > /etc/systemd/system/$SESSION_HOST_PROXY_SERVICE_NAME.service

echo "Starting session host proxy service"
systemctl daemon-reload
systemctl enable $SESSION_HOST_PROXY_SERVICE_NAME.service
systemctl restart $SESSION_HOST_PROXY_SERVICE_NAME.service # restart: idempotency

echo "Setting up Session Host proxy: DONE"
#####################/SESSION HOST PROXY/#####################

echo "Proxy installation completed"