Here's a comprehensive template for handling **OCI (Oracle Cloud Infrastructure) context** in shell scripts, including secure sourcing of credentials, configuration management, and API operations:

---

## OCI Context Sourcing Template

```bash
#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

# OCI Context Manager
# Secure sourcing of OCI configurations and authentication

### CONFIGURATION ###
OCI_CONFIG_DIR="${HOME}/.oci"
OCI_CONFIG_FILE="${OCI_CONFIG_DIR}/config"
OCI_SECRETS_DIR="${OCI_CONFIG_DIR}/secrets"
OCI_AUDIT_LOG="${OCI_CONFIG_DIR}/audit.log"

### SECURITY CONTROLS ###
init_oci_security() {
    # Set strict permissions
    mkdir -p "$OCI_CONFIG_DIR" "$OCI_SECRETS_DIR"
    chmod 700 "$OCI_CONFIG_DIR"
    chmod 600 "$OCI_CONFIG_FILE" 2>/dev/null || true
    
    # Initialize audit log
    touch "$OCI_AUDIT_LOG"
    chmod 600 "$OCI_AUDIT_LOG"
}

log_audit_event() {
    local event="$1"
    local status="${2:-SUCCESS}"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | ${event} | ${status} | User:${USER} | Host:$(hostname)" >> "$OCI_AUDIT_LOG"
}

### CONTEXT MANAGEMENT ###

# Load OCI configuration profile
load_oci_context() {
    local profile="${1:-DEFAULT}"
    local config_file="${2:-$OCI_CONFIG_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        log_audit_event "OCI_CONFIG_MISSING" "ERROR"
        echo "Error: OCI config file not found at $config_file" >&2
        return 1
    fi

    # Parse the config file safely
    while IFS='=' read -r key value; do
        [[ $key == \[*\] ]] && section=${key:1:-1} && continue
        [[ $section == "$profile" ]] || continue
        
        key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | xargs)
        value=$(echo "$value" | xargs)
        
        case $key in
            tenancy) export OCI_TENANCY="$value" ;;
            user) export OCI_USER="$value" ;;
            fingerprint) export OCI_FINGERPRINT="$value" ;;
            region) export OCI_REGION="$value" ;;
            key_file) 
                local key_path="$value"
                [[ $key_path != /* ]] && key_path="${OCI_CONFIG_DIR}/${key_path}"
                export OCI_KEY_FILE="$key_path"
                ;;
        esac
    done < <(grep -v '^#' "$config_file" | grep -v '^$')

    if [[ -z "$OCI_TENANCY" || -z "$OCI_USER" || -z "$OCI_FINGERPRINT" || -z "$OCI_REGION" || -z "$OCI_KEY_FILE" ]]; then
        log_audit_event "OCI_CONFIG_INCOMPLETE" "ERROR"
        echo "Error: Incomplete OCI configuration for profile $profile" >&2
        return 1
    fi

    log_audit_event "OCI_CONTEXT_LOADED"
}

# Secure API key passphrase handling
get_oci_passphrase() {
    local passphrase
    local passphrase_file="${OCI_SECRETS_DIR}/passphrase_${OCI_USER}_${OCI_FINGERPRINT}"
    
    if [[ -f "$passphrase_file.gpg" ]]; then
        # Decrypt passphrase using GPG (recommended)
        passphrase=$(gpg --quiet --decrypt "$passphrase_file.gpg" 2>/dev/null)
    elif [[ -f "$passphrase_file" ]]; then
        # Fallback to plaintext (not recommended)
        passphrase=$(cat "$passphrase_file")
    else
        # Interactive prompt with timeout
        read -s -t 30 -p "Enter OCI API key passphrase: " passphrase || {
            log_audit_event "OCI_PASSPHRASE_TIMEOUT" "ERROR"
            echo "Error: Passphrase input timeout" >&2
            return 1
        }
    fi
    
    export OCI_PASSPHRASE="$passphrase"
    log_audit_event "OCI_PASSPHRASE_LOADED"
}

### OCI API FUNCTIONS ###

# Authenticate and get session token
oci_authenticate() {
    local response_file=$(mktemp)
    
    # Generate secure timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Make API request
    curl --fail --silent --show-error \
        --request POST \
        --header "Content-Type: application/json" \
        --data "{
            \"tenancy\": \"$OCI_TENANCY\",
            \"user\": \"$OCI_USER\",
            \"fingerprint\": \"$OCI_FINGERPRINT\",
            \"privateKey\": \"$(sed ':a;N;$!ba;s/\n/\\n/g' "$OCI_KEY_FILE")\",
            \"passphrase\": \"$OCI_PASSPHRASE\",
            \"region\": \"$OCI_REGION\",
            \"timestamp\": \"$timestamp\"
        }" \
        "https://auth.$OCI_REGION.oraclecloud.com/v1/authenticate" > "$response_file"
    
    # Handle response
    if jq -e .token >/dev/null 2>&1 "$response_file"; then
        export OCI_SESSION_TOKEN=$(jq -r .token "$response_file")
        export OCI_SESSION_EXPIRY=$(date -d "+1 hour" -u +"%Y-%m-%dT%H:%M:%SZ")
        log_audit_event "OCI_AUTH_SUCCESS"
    else
        log_audit_event "OCI_AUTH_FAILED" "ERROR"
        echo "Error: Authentication failed" >&2
        jq . "$response_file" >&2
        return 1
    fi
    
    rm -f "$response_file"
}

# Example API call
list_oci_compartments() {
    oci_authenticate || return 1
    
    local response=$(curl --fail --silent --show-error \
        --header "Authorization: Bearer $OCI_SESSION_TOKEN" \
        "https://identity.$OCI_REGION.oraclecloud.com/v1/compartments?compartmentId=$OCI_TENANCY")
    
    echo "$response" | jq .data
}

### SECURE STORAGE TEMPLATES ###

# Encrypt OCI API key
encrypt_oci_key() {
    local key_file="$1"
    local output_file="${OCI_SECRETS_DIR}/$(basename "$key_file").gpg"
    
    gpg --output "$output_file" --encrypt --recipient "$USER" "$key_file"
    chmod 400 "$output_file"
    log_audit_event "OCI_KEY_ENCRYPTED"
}

# Store passphrase securely
store_oci_passphrase() {
    local passphrase="$1"
    local output_file="${OCI_SECRETS_DIR}/passphrase_${OCI_USER}_${OCI_FINGERPRINT}.gpg"
    
    echo "$passphrase" | gpg --output "$output_file" --encrypt --recipient "$USER"
    chmod 400 "$output_file"
    log_audit_event "OCI_PASSPHRASE_STORED"
}

### MAIN EXECUTION ###

main() {
    init_oci_security
    
    case "$1" in
        load)
            load_oci_context "${2:-DEFAULT}"
            get_oci_passphrase
            ;;
        auth)
            load_oci_context "${2:-DEFAULT}"
            get_oci_passphrase
            oci_authenticate
            echo "Session token valid until: $OCI_SESSION_EXPIRY"
            ;;
        list-compartments)
            load_oci_context "${2:-DEFAULT}"
            get_oci_passphrase
            list_oci_compartments
            ;;
        encrypt-key)
            encrypt_oci_key "$2"
            ;;
        store-passphrase)
            read -s -p "Enter passphrase to store: " passphrase
            store_oci_passphrase "$passphrase"
            ;;
        *)
            echo "Usage: $0 [load|auth|list-compartments|encrypt-key|store-passphrase] [profile?]"
            exit 1
            ;;
    esac
    
    log_audit_event "SCRIPT_COMPLETED"
}

# Only execute if not sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap 'log_audit_event "SCRIPT_ABORTED" "ERROR"' ERR
    log_audit_event "SCRIPT_STARTED"
    main "$@"
fi
```

---

## OCI Context Configuration Template (`~/.oci/config`)

```ini
[DEFAULT]
tenancy=ocid1.tenancy.oc1..aaaaaaa...
user=ocid1.user.oc1..aaaaaaa...
fingerprint=12:34:56:78:90:ab:cd:ef:12:34:56:78:90:ab:cd:ef
key_file=~/.oci/keys/oci_api_key.pem
region=us-phoenix-1

[PROD]
tenancy=ocid1.tenancy.oc1..bbbbbbb...
user=ocid1.user.oc1..bbbbbbb...
fingerprint=ab:cd:ef:12:34:56:78:90:ab:cd:ef:12:34:56:78:90
key_file=~/.oci/keys/prod_api_key.pem.gpg  # Encrypted key
region=us-ashburn-1
```

---

## Secure OCI Key Storage Structure

```
~/.oci/
├── config                  # Main config file (600)
├── audit.log               # API activity logs (600)
├── keys/
│   ├── oci_api_key.pem     # Private key (400)
│   └── prod_api_key.pem.gpg # Encrypted key (400)
└── secrets/
    ├── passphrase_USER_FINGERPRINT.gpg  # Encrypted passphrase (400)
    └── temp_creds         # Temporary credentials (600)
```

---

## Best Practices for OCI Context Scripting

1. **Credential Isolation**:
   ```bash
   # Always clean up credentials from memory
   cleanup_oci_creds() {
       unset OCI_PASSPHRASE
       unset OCI_SESSION_TOKEN
       shred -u "$OCI_TEMP_CRED_FILE" 2>/dev/null
       log_audit_event "CREDS_CLEANED"
   }
   ```

2. **Context Switching**:
   ```bash
   switch_oci_profile() {
       local profile="$1"
       cleanup_oci_creds
       load_oci_context "$profile" || return 1
       get_oci_passphrase || return 1
       oci_authenticate || return 1
   }
   ```

3. **Secure API Calls**:
   ```bash
   oci_api_request() {
       local endpoint="$1"
       local method="${2:-GET}"
       local body="${3:-null}"
       
       # Auto-refresh token if expired
       if [[ $(date -u +"%Y-%m-%dT%H:%M:%SZ") > "$OCI_SESSION_EXPIRY" ]]; then
           oci_authenticate || return 1
       fi
       
       curl --fail --silent --show-error \
           --request "$method" \
           --header "Authorization: Bearer $OCI_SESSION_TOKEN" \
           --header "Content-Type: application/json" \
           --data "$body" \
           "https://${endpoint}"
   }
   ```

4. **Configuration Validation**:
   ```bash
   validate_oci_config() {
       local required_vars=(
           OCI_TENANCY OCI_USER OCI_FINGERPRINT 
           OCI_REGION OCI_KEY_FILE
       )
       
       for var in "${required_vars[@]}"; do
           if [[ -z "${!var}" ]]; then
               echo "Error: Missing OCI configuration - $var" >&2
               return 1
           fi
       done
       
       [[ -f "$OCI_KEY_FILE" ]] || {
           echo "Error: Key file not found: $OCI_KEY_FILE" >&2
           return 1
       }
   }
   ```

5. **Error Handling**:
   ```bash
   handle_oci_error() {
       local response="$1"
       local error_code=$(jq -r '.code' <<< "$response")
       local error_msg=$(jq -r '.message' <<< "$response")
       
       case "$error_code" in
           "NotAuthenticated")
               oci_authenticate
               return 1
               ;;
           "QuotaExceeded")
               log_audit_event "API_QUOTA_EXCEEDED" "ERROR"
               return 2
               ;;
           *)
               log_audit_event "API_ERROR_${error_code}" "ERROR"
               return 3
               ;;
       esac
   }
   ```

---

## Usage Examples

1. **Sourcing OCI Context**:
```bash
# Source the script to load functions
source oci_context.sh

# Load DEFAULT profile
load_oci_context "DEFAULT"
get_oci_passphrase

# Now environment variables are available
echo "Operating in region: $OCI_REGION"
```

2. **Making Secure API Calls**:
```bash
# List all compute instances
list_instances() {
    local compartment_id=$1
    oci_api_request "iaas.$OCI_REGION.oraclecloud.com/20200930/instances?compartmentId=$compartment_id"
}

# Usage
load_oci_context "PROD"
get_oci_passphrase
list_instances "ocid1.compartment.oc1..aaaaaaa..."
```

3. **Rotating Credentials**:
```bash
rotate_oci_key() {
    local old_key="$1"
    local new_key="$2"
    
    # Store new key securely
    encrypt_oci_key "$new_key"
    
    # Update OCI config
    sed -i "s|key_file=.*|key_file=${OCI_SECRETS_DIR}/$(basename "$new_key").gpg|" "$OCI_CONFIG_FILE"
    
    # Verify new key works
    if ! oci_authenticate; then
        # Rollback on failure
        sed -i "s|key_file=.*|key_file=$old_key|" "$OCI_CONFIG_FILE"
        return 1
    fi
    
    log_audit_event "KEY_ROTATION_COMPLETE"
}
```

This template provides enterprise-grade security for OCI operations with:
- Secure credential storage (encrypted keys/passphrases)
- Comprehensive audit logging
- Automatic session management
- Defense-in-depth security controls
- Error handling and recovery mechanisms

For production use:
1. Store the master script in a secure location (`/usr/local/lib/oci/`)
2. Set strict permissions (`chmod 750`)
3. Configure regular credential rotation
4. Monitor the audit log for suspicious activity

