#!/bin/bash
set -euo pipefail

LDAP_SCHEMA_FILES=("core.ldif" "cosine.ldif" "inetorgperson.ldif" "eduperson.ldif" "schac.ldif" "dfneduperson.ldif")

# Internal path variables
export LDAP_DATA_DIR="${LDAP_DATA_DIR:="/var/lib/ldap"}"
export LDAP_BASE_DIR="${LDAP_BASE_DIR:="/etc/openldap"}"
export LDAP_CONFIG_DIR="${LDAP_CONFIG_DIR:="/etc/openldap/slapd.d"}"
export LDAP_SCHEMA_DIR="${LDAP_SCHEMA_DIR:="/etc/openldap/schema"}"
export LDAP_INIT_DIR="${LDAP_INIT_DIR:="/etc/openldap/init"}"

# Import LDAP Schema Files
for schema_file in "${LDAP_SCHEMA_FILES[@]}"; do
    schema_path="${LDAP_SCHEMA_DIR}/${schema_file}"
    if [[ -f "$schema_path" ]]; then
        echo "Importing: $schema_file"
        slapadd -n 0 -F ${LDAP_CONFIG_DIR} -l "$schema_path"
    else
        echo "Warn: Schema file $schema_path not found!"
    fi
done