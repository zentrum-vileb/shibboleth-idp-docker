# Functions
exportVariables() {
    echo "Exporting environment variables..."
    if [ ! -f ".env" ]; then
      cp ./.env.example ./.env
    fi
    if [ -f ".env" ]; then
        setVariables
        tmpfile=$(mktemp)
        grep -v '^\s*#' ".env" | sed 's/^\s*//;s/\s*$//' | grep -E '^[A-Za-z0-9_-]=*' > "$tmpfile"
        while IFS='=' read -r key value; do
            # Trim quotes
            value="${value%\"}"
            value="${value#\"}"

            # Resolve references to other environment variables (must be declared before)
            if [[ "$value" == *\$\{* ]]; then
              # Check if the key is in the list of excluded values
              value=$(echo $value | envsubst)
            fi
            # Export the variable safely
            export "$key"="$value"
        done < "$tmpfile"
        rm "$tmpfile"
        # Ensure we have a user to run services
        addUser
        #Debugging
        #env | sort
        #exit 1
    else
        echo "No .env file found. Exiting..."
        exit 1
    fi
}

setVariables() {
  env_vars=$(grep -v '^\s*#' ".env" | grep -E '^[A-Za-z0-9_-]*=' | sed 's/=.*//' | sed 's/^/$/' | tr '\n' ',' | sed 's/,$//')
}

initConfig() {
  echo "No config found, initializing..."
  updateConfig
  updateDfnSchema
  updateDfnMetadataCertificate
  updateShibbolethPgpKeys
  updatePermissions
  restartIDPContainer
}

addUser() {

  # check if we can create users and groups
  local commands=("getent" "id" "groupadd" "usermod" "useradd")
  for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Note: Cannot create user or group for idp service in this environment. Try if default works or create user and group manually."
            return 1
        fi
  done

  EXISTING_GROUPID_BY_NAME=$(getent group "$CONTAINER_USER_GROUPNAME" | cut -d: -f3)
  EXISTING_GROUPNAME_BY_ID=$(getent group "$CONTAINER_GID" | cut -d: -f1)
  EXISTING_USERID_BY_NAME=$(id -u "$CONTAINER_USER_NAME" 2>/dev/null)
  EXISTING_USERNAME_BY_ID=$(getent passwd "$CONTAINER_UID" | cut -d: -f1)

  # Check if group name matches .env
  if [ -n "$EXISTING_GROUPNAME_BY_ID" ] && [ "$EXISTING_GROUPNAME_BY_ID" != "$CONTAINER_USER_GROUPNAME"  ]; then
    read -r -p "Warning: Mismatch of group name. Existing group: '$EXISTING_GROUPNAME_BY_ID'. Expected from container_user_groupname: '$CONTAINER_USER_GROUPNAME', review your .env. Continue anyway? [y/N] " DO_CONTINUE_ADD_USER
    if [[ ! "$DO_CONTINUE_ADD_USER" =~ ^([yY])+$ ]]; then
      echo "Exiting..."
      exit 1
    fi
  fi

  # Check if group id matches .env
  if [ -n "$EXISTING_GROUPID_BY_NAME" ] && [ "$EXISTING_GROUPID_BY_NAME" != "$CONTAINER_GID" ]; then
    echo "Error: Mismatch of group id: '$EXISTING_GROUPID_BY_NAME', expected .env container_gid '$CONTAINER_GID', review your .env."
    exit 1
  fi

  # Check if user name matches .env
  if [ -n "$EXISTING_USERNAME_BY_ID" ] && [ "$EXISTING_USERNAME_BY_ID" != "$CONTAINER_USER_NAME" ]; then
    read -r -p "Warning: User already exists as '$EXISTING_USERNAME_BY_ID' ($CONTAINER_UID). Expected from container_user_name: '$CONTAINER_USER_NAME' ($CONTAINER_UID), review your .env. Continue anyway? [y/N] " DO_CONTINUE_ADD_USER
    if [[ ! "$DO_CONTINUE_ADD_USER" =~ ^([yY])+$ ]]; then
      echo "Exiting..."
      exit 1
    fi
  fi

  # Check if user id of local user name matches .env
  if [ -n "$EXISTING_USERID_BY_NAME" ] && [ "$EXISTING_USERID_BY_NAME" != "$CONTAINER_UID" ]; then
    read -r -p "Warning: User '$CONTAINER_USER_NAME' ($EXISTING_USERID_BY_NAME) already exists, expected user id '$CONTAINER_UID', review your .env. Continue anyway? [y/N] " DO_CONTINUE_ADD_USER
    if [[ ! "$DO_CONTINUE_ADD_USER" =~ ^([yY])+$ ]]; then
      echo "Exiting..."
      exit 1
    fi
  fi
 
  # Check if the group exists, otherwise, create it
  if [ -z "$EXISTING_GROUPID_BY_NAME" ] && [ -z "$EXISTING_GROUPNAME_BY_ID" ]; then
    echo "Creating group '$CONTAINER_USER_GROUPNAME' ($CONTAINER_GID) for service..."

    if ! groupadd -g "$CONTAINER_GID" "$CONTAINER_USER_GROUPNAME"; then
      read -r -p "Error: Failed to create group. Continue anyway? [y/N] " DO_CONTINUE
      if [[ ! "$DO_CONTINUE" =~ ^([yY])+$ ]]; then
        echo "Exiting..."
        exit 1
      fi
    fi

    EXISTING_GROUPID_BY_NAME=$(getent group "$CONTAINER_USER_GROUPNAME" | cut -d: -f3)
    EXISTING_GROUPNAME_BY_ID=$(getent group "$CONTAINER_GID" | cut -d: -f1)
  fi

  if getent group "$CONTAINER_GID" > /dev/null; then
    if [ -n "$EXISTING_USERNAME_BY_ID" ];  then
      # User exists, check if user is in the group
      if ! id -G "$CONTAINER_UID" | grep -q "\b$CONTAINER_GID\b"; then
          echo "Adding existing user $EXISTING_USERNAME_BY_ID ($CONTAINER_UID) to group $EXISTING_GROUPNAME_BY_ID ($CONTAINER_GID)..."
          usermod -aG "$EXISTING_GROUPNAME_BY_ID" "$EXISTING_USERNAME_BY_ID" || { echo "Error: Failed to add user to group."; exit 1; }
      fi
    else
      if [ -n "$EXISTING_USERID_BY_NAME" ];  then
        echo "Error: Cannot add user. Duplicate user name, different id: '$CONTAINER_USER_NAME' ($EXISTING_USERID_BY_NAME), expected $CONTAINER_USER_NAME ($CONTAINER_UID), review .env"
        exit 1
      else
        echo "Creating user '$CONTAINER_USER_NAME' ($CONTAINER_UID) in group '$EXISTING_GROUPNAME_BY_ID' ($CONTAINER_GID) for service..."
        useradd -u $CONTAINER_UID -g "$CONTAINER_GID" -m "$CONTAINER_USER_NAME" -s /sbin/nologin || { echo "Error: Failed to create user."; exit 1; }
      fi
    fi
  fi
}

# Update permissions on docker host
updatePermissions() {
  FOLDERS="$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_CONFIG_SHIBIDP/metadata $IDP_HOST_COMMON_LOG_PATH"

  echo -e "Set permissions on mounted folders (chown $CONTAINER_UID:$CONTAINER_GID, chmod g+rwX)..."

  # Loop through each folder
  for TARGET_FOLDER in $FOLDERS; do
      if [ -d "$TARGET_FOLDER" ]; then
          echo "Updating permissions for $TARGET_FOLDER..."
          
          # Change ownership
          chown -R "$CONTAINER_UID:$CONTAINER_GID" "$TARGET_FOLDER"

          # Ensure the user and group have write permissions
          chmod -R g+rwX "$TARGET_FOLDER"
      else
          echo "Warning: Folder $TARGET_FOLDER does not exist, skipping..."
      fi
  done
}

backupConfig() {
  if [ ! -d "$IDP_HOST_PATH_CONTAINER_FILES_BACKUP" ]; then
    mkdir -p "$IDP_HOST_PATH_CONTAINER_FILES_BACKUP"
  fi
  # Backup configuration and substituting variables
  echo "Creating backup of configuration files..."
  if cp -r "$IDP_HOST_PATH_CONTAINER_FILES/." "$IDP_HOST_PATH_CONTAINER_FILES_BACKUP/$(date +'%Y%m%d_%H%M%S')/"; then
    echo "Backup successful."
  else
    return 1
  fi
}

updateConfig() {
    # Initialize configuration from templates if not existing
    if [ ! -d "$IDP_HOST_PATH_CONTAINER_FILES" ]; then
      mkdir -p "$IDP_HOST_PATH_CONTAINER_FILES"
      cp -r "$IDP_HOST_PATH_CONTAINER_FILES_TEMPLATES/." "$IDP_HOST_PATH_CONTAINER_FILES/"
    fi

    if backupConfig; then
      echo "Begin substituting variables in configuration files, this can take up to a minute..."
      #echo $env_vars
      for template_file in $(find "$IDP_HOST_PATH_CONTAINER_FILES_TEMPLATES" -type f -regex "$INCLUDED_FILE_REGEX"); do
          if [ -f "$template_file" ]; then
            target_file="$IDP_HOST_PATH_CONTAINER_FILES/$(realpath --relative-to="$IDP_HOST_PATH_CONTAINER_FILES_TEMPLATES" "$template_file")"
            echo "Processing $target_file"

            # Substitute environment variables
            envsubst "$env_vars" < "$template_file" > "$template_file.tmp"
            mkdir -p "$(dirname "$target_file")"
            mv "$template_file.tmp" "$target_file"
          fi
      done
      echo "Done."
    else
      echo "Backup failed. Exiting..."
      exit 1
    fi
}

updateSamlMetadata() {
  XML_IDP_METADATA_FILE=$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_CONFIG_SHIBIDP/metadata/idp-metadata.xml
  echo "Updating saml certificate in $XML_IDP_METADATA_FILE..."
  
  # Read and update the certificate contents
  CERT_SIGNING_CONTENT=$(sed '1d;$d' "$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_SECRETS_SHIBIDP/$IDP_SAML_FILE_SIGNING_CERT.next")
  CERT_ENCRYPTION_CONTENT=$(sed '1d;$d' "$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_SECRETS_SHIBIDP/$IDP_SAML_FILE_ENCRYPTION_CERT.next")

  # Escape special characters and remove whitespace
  ESCAPED_CERT_SIGNING_CONTENT=$(echo "$CERT_SIGNING_CONTENT" | tr -d '[:space:]' | sed -e 's/[\/&]/\\&/g')
  ESCAPED_CERT_ENCRYPTION_CONTENT=$(echo "$CERT_ENCRYPTION_CONTENT" | tr -d '[:space:]' | sed -e 's/[\/&]/\\&/g')

  # Replace the <ds:X509Certificate> content under "signing"
  sed -i -E "/<KeyDescriptor use=\"signing\">/,/<\/md:KeyDescriptor>/s|(<ds:X509Certificate>).*?(</ds:X509Certificate>)|\1$ESCAPED_CERT_SIGNING_CONTENT\2|g" "$XML_IDP_METADATA_FILE"

  # Replace the <ds:X509Certificate> content under "encryption"
  sed -i -E "/<KeyDescriptor use=\"encryption\">/,/<\/md:KeyDescriptor>/s|(<ds:X509Certificate>).*?(</ds:X509Certificate>)|\1$ESCAPED_CERT_ENCRYPTION_CONTENT\2|g" "$XML_IDP_METADATA_FILE"
}

backupServices() {
  backupConfig
  backupMariaDB
  #backupLDAP (not implemented)
}

# Backup MariaDB databse in official container image
# https://mariadb.com/kb/en/container-backup-and-restoration/
backupMariaDB() {
    local BACKUP_FILE="$(date +'%Y%m%d_%H%M%S')_mariadb_backup.sql"
    if [ ! -d "$MARIADB_PATH_BACKUP" ]; then
      mkdir -p "$MARIADB_PATH_BACKUP"
    fi
    echo "Creating backup of container: $MARIADB_CONTAINER_NAME..." 
    if docker compose -f "$COMPOSE_FILE" exec $MARIADB_CONTAINER_NAME mariadb-dump --all-databases -u"${MARIADB_ROOT_USER}" -p"$MARIADB_ROOT_PASSWORD" > "$MARIADB_PATH_BACKUP/${BACKUP_FILE}"; then
       echo "Backup of $MARIADB_CONTAINER_NAME successful."
      return 1
    else
      echo "Backup of $MARIADB_CONTAINER_NAME failed."
      read -r -p "WARNING: Do you want to continue with a failed backup? [y/N] " DO_CONTINUE_FAILED_BACKUP
      if [[ ! "$DO_CONTINUE_FAILED_BACKUP" =~ ^([yY])+$ ]]; then
        echo "Exiting due to failed backup of $MARIADB_CONTAINER_NAME."
        exit 1
      fi
    fi
}

# Get the latest metadata certificate from DFN-AAI to verify signed SP/IDP saml metadata
updateDfnSchema() {
  echo -e "\nGet schema from DFN-AAI...\n"
  dfn_schema_base_url="https://download.aai.dfn.de/schema"
  dfn_schema_files=("dfnEduPerson.xml" "dfnMisc.xml")

  for schema_file in "${dfn_schema_files[@]}"; do
    target_file="$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_CONFIG_SHIBIDP/conf/attributes/$schema_file"
    target_file_template="$IDP_HOST_PATH_CONTAINER_FILES_TEMPLATES/$IDP_HOST_SUBPATH_CONFIG_SHIBIDP/conf/attributes/$schema_file"
    curl -o "$target_file_template.tmp" "$dfn_schema_base_url/$schema_file"
    if ! cmp -s "$target_file_template.tmp" "$target_file_template"; then
        echo -e "\nUpdating schema file: $schema_file...\n"
        cp "$target_file_template.tmp" "$target_file"
        mv "$target_file_template.tmp" "$target_file_template"
      else 
        rm "$target_file_template.tmp"
      fi
  done
}


# Get the latest metadata certificate from DFN-AAI to verify signed SP/IDP saml metadata
updateDfnMetadataCertificate() {
  echo -e "\nGet metadata certificate from DFN-AAI...\n"
  pem_filename=$(basename "$IDP_DFNAAI_METADATA_CERT_URL")
  pem_file="$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_SECRETS_AAI/$pem_filename"
  pem_file_template="$IDP_HOST_PATH_CONTAINER_FILES_TEMPLATES/$IDP_HOST_SUBPATH_SECRETS_AAI/$pem_filename"
  expected_fingerprint="$IDP_DFNAAI_METADATA_CERT_SHA256_FINGERPRINT"

  # Update template file and copy to configuration folder
  curl -o "$pem_file_template.tmp" "$IDP_DFNAAI_METADATA_CERT_URL"
  if [ $? -eq 0 ]; then
    if verify_fingerprint "$pem_file_template.tmp" "$expected_fingerprint"; then
        echo -e "\nVerifed fingerprint of metadata certificate."
        # compare files, only copy if different
        if ! cmp -s "$pem_file_template.tmp" "$pem_file"; then
          echo "Updating metadata certificate..."
          cp "$pem_file_template.tmp" "$pem_file"
          mv "$pem_file_template.tmp" "$pem_file_template"
        else 
          echo "Metadata certificate already up to date."
          rm "$pem_file_template.tmp"
        fi
    else
      echo "Verification of fingerprint failed. Check if .env contains latest fingerprint from $IDP_DFNAAI_METADATA_CERT_URL_DOCU."
    fi
  fi
}

# Get the latest pgp keys
updateShibbolethPgpKeys() {
  echo -e "\nGet pgp keys from Shibboleth...\n"
  truststore="$IDP_HOST_PATH_CONTAINER_FILES/$IDP_HOST_SUBPATH_SECRETS_SHIBIDP/PGP_KEYS"
  truststore_template="$IDP_HOST_PATH_CONTAINER_FILES_TEMPLATES/$IDP_HOST_SUBPATH_SECRETS_SHIBIDP/PGP_KEYS"

  # Update template file and copy to configuration folder
  curl -o "$truststore_template.tmp" "$IDP_SHIBBOLETH_PGP_KEYS_URL"
  if [ $? -eq 0 ]; then
    # compare files, only copy if different
    if ! cmp -s "$truststore_template.tmp" "$truststore"; then
      echo -e "\nUpdating pgp keys ..."
      cp "$truststore_template.tmp" "$truststore"
      mv "$truststore_template.tmp" "$truststore_template"
      
      # Update gpg keyring within docker container
      if docker compose -f "$COMPOSE_FILE" exec $IDP_CONTAINER_NAME /bin/sh -c "
        gpg --refresh-keys
        gpg --import $IDP_SAML_PATH_CERT/PGP_KEYS
      "; then
        echo "Shibboleth PGP Keys imported within container."
      else
        echo "NOTE: Failed to import shibboleth pgp keys within container."
      fi

    else 
      echo -e "\nPGP keys already up to date."
      rm "$truststore_template.tmp"
    fi
  fi
}


# Generate self signed certificate for signing/encryption of IDP
generateSelfSignedCertificate() {
  read -r -p "Do you want to create new self signed saml certificates? [y/N] " DO_CONTINUE_CREATE_SAML_CERT
  if [[ "$DO_CONTINUE_CREATE_SAML_CERT" =~ ^([yY])+$ ]]; then
    echo "Generating self-signed certificates..."
    if docker compose -f "$COMPOSE_FILE" exec $IDP_CONTAINER_NAME /bin/sh -c "
      cd $IDP_SAML_PATH_CERT && \
      rm -f $IDP_SAML_FILE_ENCRYPTION_CERT.next && \
      rm -f $IDP_SAML_FILE_SIGNING_CERT.next && \
      rm -f $IDP_SAML_FILE_ENCRYPTION_KEY.next && \
      rm -f $IDP_SAML_FILE_SIGNING_KEY.next && \
      cd $IDP_CONTAINER_PATH_BIN && \
      $IDP_CONTAINER_PATH_BIN/keygen.sh \
        --lifetime 3 \
        --size 4096 \
        --certfile $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_CERT.next \
        --keyfile $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_KEY.next \
        --hostname $IDP_SAML_CERT_FQDN && \
      $IDP_CONTAINER_PATH_BIN/keygen.sh \
        --lifetime 3 \
        --size 4096 \
        --certfile $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_CERT.next \
        --keyfile $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_KEY.next \
        --hostname $IDP_SAML_CERT_FQDN && \
      chmod 600 $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_CERT.next && \
      chmod 600 $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_CERT.next && \
      chown --reference $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_KEY $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_KEY.next && \
      chown --reference $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_KEY $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_KEY.next
    "; then
      echo "Certificates generated successfully."
      updateSamlMetadata # Update metadata with new certificates
    else
      echo "Failed to generate certificates. Exiting..."
      exit 1
    fi
  fi
}

# Rollover self signed certificates for signing/encryption of IDP
rolloverSelfSignedCertificates() {
  read -r -p "Do you want to rollover self signed saml certificates (replace current saml certificate)? [y/N] " DO_CONTINUE_ROLLOVER_SAML_CERT
  if [[ "$DO_CONTINUE_ROLLOVER_SAML_CERT" =~ ^([yY])+$ ]]; then
      echo "Rollover self-signed certificates..."
      if docker compose -f "$COMPOSE_FILE" exec $IDP_CONTAINER_NAME /bin/sh -c "
        cd $IDP_SAML_PATH_CERT && \
        mkdir -p ./backup && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_CERT "./backup/$(date +'%Y%m%d_%H%M%S')_idp-encryption.crt.old" && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_CERT "./backup/$(date +'%Y%m%d_%H%M%S')_idp-signing.crt.old" && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_KEY "./backup/$(date +'%Y%m%d_%H%M%S')_idp-encryption.key.old" && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_KEY "./backup/$(date +'%Y%m%d_%H%M%S')_idp-signing.key.old" && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_CERT.next $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_CERT && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_CERT.next $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_CERT && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_KEY.next $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_ENCRYPTION_KEY && \
        cp $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_KEY.next $IDP_SAML_PATH_CERT/$IDP_SAML_FILE_SIGNING_KEY
      "; then
        echo "Certificates rolled over successfully."
        updateSamlMetadata # Should already be up to date
    else
      echo "Failed to roll over certificates. Exiting..."
      exit 1
    fi
  fi
}

rebuildWar() {
  read -r -p "Do you want to rebuild the idp war? [y/N] " DO_REBUILD_IDP_WAR
  if [[ "$DO_REBUILD_IDP_WAR" =~ ^([yY])+$ ]]; then
    if ! docker compose -f "$COMPOSE_FILE" exec $IDP_CONTAINER_NAME /bin/sh -c "
      $IDP_CONTAINER_PATH_BIN/build.sh
    "; then
      echo "Failed to rebuild idp war. Exiting..."
      exit 1
    fi
  fi
}

restartIDPContainer() {
  read -r -p "Do you want to restart the idp container? [y/N] " DO_RESTART_IDP_CONTAINER
  if [[ "$DO_RESTART_IDP_CONTAINER" =~ ^([yY])+$ ]]; then
    if ! docker compose -f "$COMPOSE_FILE" restart $IDP_CONTAINER_NAME; then
      echo "Failed to restart tomcat service. Exiting..."
      exit 1
    fi
  fi
}

verify_fingerprint() {
    local pem_file=$1
    local expected_fingerprint=$2

    # Get the SHA-256 fingerprint from the .pem file
    local current_fingerprint=$(openssl x509 -noout -in "$pem_file" -fingerprint -sha256 | awk -F= '{print $2}')

    # Compare the extracted fingerprint with the expected fingerprint
    if [ "$current_fingerprint" = "$expected_fingerprint" ]; then
        return 0
    else
        return 1
    fi
}

# Init
exportVariables