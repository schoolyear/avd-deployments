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

##################### HELPER FUNCTIONS #####################

# Calculates the moduli of a certificate and it's private key
# returns 0 on match and 1 on mismatch
check_key_match() {
  local private_key="$1"
  local public_key="$2"

  # Extract modulus from the private key
  private_modulus=$(openssl rsa -in "$private_key" -noout -modulus | openssl md5)
  if [[ $? -ne 0 ]]; then
    echo "check_key_match: Unable to process private key."
    return 1
  fi

  # Extract modulus from the public key
  public_modulus=$(openssl x509 -in "$public_key" -noout -modulus | openssl md5)
  if [[ $? -ne 0 ]]; then
    echo "check_key_match: Unable to process public key."
    return 1
  fi

  # Compare the moduli
  if [[ "$private_modulus" == "$public_modulus" ]]; then
    return 0
  else
    return 1
  fi
}

# Reverses the order of a certificate chain
reverse_certificates() {
  local public_key="$1"
  local dir="$(dirname "$public_key")"
  local reordered_key="$dir/reordered_public.pem"
  local temp_reordered_key="$dir/temp_reordered.pem"

  # Split the public.pem file into individual certificate files
  # by using the 'END CERTIFICATE' as separating line
  csplit -f cert_part_ -z "$public_key" '/END CERTIFICATE/+1' '{*}' >/dev/null 2>&1

  # Go over the split certificate and reverse their order
  touch $reordered_key
  for cert_file in cert_part_*; do
    cat $cert_file "$reordered_key" > "$temp_reordered_key"
    mv "$temp_reordered_key" "$reordered_key"
  done

  # Replace the original file with reordered content
  mv "$reordered_key" "$public_key"
  echo "Certificates reordered in $public_key"

  # Cleanup temporary certificate parts
  rm -f cert_part_*
}

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

# this uses python because it is pre-installed on Ubuntu
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

# Sometimes the certificate chain is in reverse order
# (ACME KeyVault does this occasionally for example)
# We check the moduli of private - public keys and if 
# there is a mismatch we try again with a reverse certificate 
# chain. If moduli is a mismatch again we give up.
echo "Checking private - public moduli"
if check_key_match "$TRUSTED_PROXY_PRIV_KEY_PATH" "$TRUSTED_PROXY_CERT_PATH"; then
  echo "Keys match, doing nothing"
else
  echo "Private key does not match public key"
  echo "Attempting to fix mismatch by reversing order of certificate chain"
  reverse_certificates "$TRUSTED_PROXY_CERT_PATH"
  if check_key_match "$TRUSTED_PROXY_PRIV_KEY_PATH" "$TRUSTED_PROXY_CERT_PATH"; then
    echo "Reorder was successfull"
  else
    echo "Keys still don't match, exiting"
    exit 55
  fi
fi

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

# Check if trusted proxy is up and running
if systemctl is-active --quiet "$TRUSTED_PROXY_SERVICE_NAME.service"; then
  echo "Service $TRUSTED_PROXY_SERVICE_NAME is active"
else
  echo "Service $TRUSTED_PROXY_SERVICE_NAME failed to start" >&2
  exit 53
fi

# Check Trusted proxy readiness
MAX_RETRIES=3
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
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
  COUNT=$((COUNT+1))
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
MAX_RETRIES=3
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
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
  COUNT=$((COUNT+1))
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