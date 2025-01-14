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
TRUSTED_PROXY_FQDN=$9             # when set, the script verifies if it gets a valid certificate when trying to connect to the trusted proxy
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

##################### HELPER FUNCTIONS #####################

#####################/HELPER FUNCTIONS/#####################

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
TRUSTED_PROXY_PORT="443"

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
echo "Request Entra token"
ENTRA_URL="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"

ENTRA_MAX_RETRIES=5
ENTRA_RETRY_COUNT=0
while [ $ENTRA_RETRY_COUNT -lt $ENTRA_MAX_RETRIES ]; do
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
  ENTRA_RETRY_COUNT=$((ENTRA_RETRY_COUNT+1))
  sleep 10
done

if [ "$ENTRA_STATUS" -ne 200 ]; then
  echo "Failed with status code $ENTRA_STATUS"
  echo "Response body:"
  echo "$ENTRA_BODY"
  exit 51
fi

# this uses python because it is pre-installed on Ubuntu
echo "Parsing access_token from Entra token response"
ACCESS_TOKEN=$(echo $ENTRA_BODY | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Get TLS certificate
echo "Fetching TLS certificate from Key Vault"
KEYVAULT_URL="https://$CERT_VAULT_NAME.vault.azure.net/secrets/$CERT_NAME?api-version=7.4"
KEYVAULT_MAX_RETRIES=5
KEYVAULT_RETRY_COUNT=0

while [ $KEYVAULT_RETRY_COUNT -lt $KEYVAULT_MAX_RETRIES ]; do
  CERT_RESPONSE=$(curl -s -o - -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" $KEYVAULT_URL) || {
      echo "Curl failed to fetch TLS certificate from keyvault with exit code $? (see https://everything.curl.dev/cmdline/exitcode.html): $KEYVAULT_URL"
      exit 49
  }

  CERT_STATUS="${CERT_RESPONSE: -3}"
  CERT_BODY="${CERT_RESPONSE:0:${#CERT_RESPONSE}-3}"

  if [ "$CERT_STATUS" -eq 200 ]; then
    break
  fi

  echo "request failed with ($CERT_STATUS): $CERT_BODY"
  echo "retrying..."
  KEYVAULT_RETRY_COUNT=$((KEYVAULT_RETRY_COUNT+1))

  if [ "$CERT_STATUS" -eq 403 ]; then
    # the most common cause for Key Vault failure is 403 caused by slow RBAC propagation in Azure
    # we wait 5x 1min, which should be enough for Azure™®© to get its shit together
    sleep 60
  else
    sleep 10
  fi
done

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
ExecStart=$BINARY_PATH -api-key $TRUSTED_PROXY_API_KEY_PATH -host-whitelist $TRUSTED_PROXY_WHITELIST_PATH -tls-cert $TRUSTED_PROXY_CERT_PATH -tls-key $TRUSTED_PROXY_PRIV_KEY_PATH -listen-address :$TRUSTED_PROXY_PORT -api-base-url $API_BASE_URL -auth-bypass $TRUSTED_PROXY_AUTH_BYPASS_PATH
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=default.target" > /etc/systemd/system/$TRUSTED_PROXY_SERVICE_NAME.service

echo "Starting trusted proxy service"
systemctl daemon-reload
systemctl enable $TRUSTED_PROXY_SERVICE_NAME.service
systemctl restart $TRUSTED_PROXY_SERVICE_NAME.service # restart: idempotency

# Check if trusted proxy is up and running
if systemctl is-active --quiet "$TRUSTED_PROXY_SERVICE_NAME.service"; then
  echo "Service $TRUSTED_PROXY_SERVICE_NAME is active"
else
  echo "Service $TRUSTED_PROXY_SERVICE_NAME failed to start" >&2
  exit 53
fi

if [ "$TRUSTED_PROXY_FQDN" -ne "" ]; then
  SCLIENT_OUTPUT=$(echo -n | openssl s_client -connect 127.0.0.1:$TRUSTED_PROXY_PORT -servername "$TRUSTED_PROXY_FQDN" -verify_hostname "$TRUSTED_PROXY_FQDN" -verify_return_error)
  echo "Trusted Proxy connection test:"
  echo "$SCLIENT_OUTPUT"

  if echo "$SCLIENT_OUTPUT" | grep -q "Verify return code: 0 (ok)"; then
    echo "Certificate verification succeeded."
  else
    echo "Certificate verification failed."
    exit 57
  fi
fi

# Check Trusted proxy readiness
TP_MAX_RETRIES=3
TP_RETRY_COUNT=0
while [ $TP_RETRY_COUNT -lt $TP_MAX_RETRIES ]; do
  TRUSTED_PROXY_READY_RESPONSE=$(curl --insecure -s -o - -w "%{http_code}" "https://localhost/ready") || {
    echo "Curl failed to check trusted proxy /ready with exit code $? (see https://everything.curl.dev/cmdline/exitcode.html)"
  }
  TRUSTED_PROXY_READY_STATUS="${TRUSTED_PROXY_READY_RESPONSE: -3}"
  TRUSTED_PROXY_READY_BODY="${TRUSTED_PROXY_READY_RESPONSE:0:${#TRUSTED_PROXY_READY_RESPONSE}-3}"
  if [ "$TRUSTED_PROXY_READY_STATUS" -eq 200 ]; then
    break
  fi

  echo "Trusted proxy readiness check failed with status: $TRUSTED_PROXY_READY_STATUS"
  echo "Response Body:"
  echo $TRUSTED_PROXY_READY_BODY
  TP_RETRY_COUNT=$((TP_RETRY_COUNT+1))
  sleep 2
done

if [ "$TRUSTED_PROXY_READY_STATUS" -ne 200 ]; then
  echo "All Trusted proxy readiness checks failed, last status: $TRUSTED_PROXY_READY_STATUS"
  echo "Response body:"
  echo $TRUSTED_PROXY_READY_BODY
  exit 54
fi

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

# Check if Session Host proxy is up and running
if systemctl is-active --quiet "$SESSION_HOST_PROXY_SERVICE_NAME.service"; then
  echo "Service $SESSION_HOST_PROXY_SERVICE_NAME is active"
else
  echo "Service $SESSION_HOST_PROXY_SERVICE_NAME failed to start" >&2
  exit 53
fi

# Check Session Host proxy readiness
SP_MAX_RETRIES=3
SP_RETRY_COUNT=0
while [ $SP_RETRY_COUNT -lt $SP_MAX_RETRIES ]; do
  SESSION_HOST_PROXY_READY_RESPONSE=$(curl -s -o - -w "%{http_code}" "http://localhost:8080/ready") || {
    echo "Curl failed to check session host proxy /ready with exit code $? (see https://everything.curl.dev/cmdline/exitcode.html)"
  }
  SESSION_HOST_PROXY_READY_STATUS="${SESSION_HOST_PROXY_READY_RESPONSE: -3}"
  SESSION_HOST_PROXY_READY_BODY="${SESSION_HOST_PROXY_READY_RESPONSE:0:${#SESSION_HOST_PROXY_READY_RESPONSE}-3}"
  if [ "$SESSION_HOST_PROXY_READY_STATUS" -eq 200 ]; then
    break
  fi

  echo "Session Host proxy readiness check failed with status: $SESSION_HOST_PROXY_READY_STATUS"
  echo "Response Body:"
  echo $SESSION_HOST_PROXY_READY_BODY
  SP_RETRY_COUNT=$((SP_RETRY_COUNT+1))
  sleep 2
done

if [ "$SESSION_HOST_PROXY_READY_STATUS" -ne 200 ]; then
  echo "All Session Host proxy readiness checks failed, last status: $SESSION_HOST_PROXY_READY_STATUS"
  echo "Response body:"
  echo $SESSION_HOST_PROXY_READY_BODY
  exit 54
fi

echo "Setting up Session Host proxy: DONE"
#####################/SESSION HOST PROXY/#####################

echo "Proxy installation completed"