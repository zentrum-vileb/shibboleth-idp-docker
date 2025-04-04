#!/bin/bash
set -euo pipefail

# Environement variables
export IDP_LDAP_BIND_BASE_DN="${IDP_LDAP_BIND_BASE_DN:="dc=test,dc=example,dc=org"}"
export IDP_LDAP_BASE_OU_SYSTEMUSERS="${IDP_LDAP_BASE_OU_SYSTEMUSERS:="ou=systemusers,dc=test,dc=example,dc=org"}"
export IDP_LDAP_BASE_OU_USERS="${IDP_LDAP_BASE_OU_USERS:="ou=accounts,dc=test,dc=example,dc=org"}"
export IDP_LDAP_BIND_DN_ADMIN="${IDP_LDAP_BIND_DN_ADMIN:="cn=admin,ou=systemusers,dc=test,dc=example,dc=org"}"
export IDP_LDAP_BIND_DN_IDP="${IDP_LDAP_BIND_DN_IDP:="cn=idp,ou=systemusers,dc=test,dc=example,dc=org"}"
export IDP_LDAP_ADMIN_PASSWORD="${IDP_LDAP_ADMIN_PASSWORD:="changeme"}"
export IDP_LDAP_IDPUSER_PASSWORD="${IDP_LDAP_IDPUSER_PASSWORD:="shibboleth"}"
export IDP_LDAP_TESTUSER_PASSWORD="${IDP_LDAP_TESTUSER_PASSWORD:="test"}"
export IDP_LDAP_OLC_DB_INDEX="${IDP_LDAP_OLC_DB_INDEX:="cn"}"
export IDP_LDAP_ORGANIZATION_NAME="${IDP_LDAP_ORGANIZATION_NAME:="Test Organization"}"

# Internal path variables
export LDAP_DATA_DIR="${LDAP_DATA_DIR:="/var/lib/ldap"}"
export LDAP_BASE_DIR="${LDAP_BASE_DIR:="/etc/openldap"}"
export LDAP_CONFIG_DIR="${LDAP_CONFIG_DIR:="/etc/openldap/slapd.d"}"
export LDAP_SCHEMA_DIR="${LDAP_SCHEMA_DIR:="/etc/openldap/schema"}"
export LDAP_INIT_DIR="${LDAP_INIT_DIR:="/etc/openldap/init"}"

# Hash passwords (SHA-512)
hash_password() {
    local password="$1"
    if [[ ! "$password" =~ ^\{CRYPT\} ]]; then
        password=$(slappasswd -s "$password" -h '{CRYPT}' -c "\$6\$%.16s")
    fi
    echo "$password"
}

if [ ! -f "$LDAP_INIT_DIR/initialized" ]; then
    echo "Initializing OpenLDAP configuration..."

    # Hash passwords
    export IDP_LDAP_ADMIN_PASSWORD=$(hash_password "$IDP_LDAP_ADMIN_PASSWORD")
    export IDP_LDAP_IDPUSER_PASSWORD=$(hash_password "$IDP_LDAP_IDPUSER_PASSWORD")
    export IDP_LDAP_TESTUSER_PASSWORD=$(hash_password "$IDP_LDAP_TESTUSER_PASSWORD")

    # Substitute env vars
    envsubst < $LDAP_INIT_DIR/db.ldif > $LDAP_INIT_DIR/db.tmp.ldif
    envsubst < $LDAP_INIT_DIR/users.ldif > $LDAP_INIT_DIR/users.tmp.ldif

    # Init database config
    slapadd -n 0 -F $LDAP_CONFIG_DIR -l $LDAP_INIT_DIR/db.tmp.ldif

    # Init Schemas (Import the schemas)
    echo "Importing LDAP schemas..."
    $LDAP_BASE_DIR/importSchema.sh

    # Init objects (e.g. users) to mdb database
    slapadd -n 2 -F $LDAP_CONFIG_DIR -l $LDAP_INIT_DIR/users.tmp.ldif

    # Cleanup
    rm -f $LDAP_INIT_DIR/db.tmp.ldif
    rm -f $LDAP_INIT_DIR/users.tmp.ldif

    touch $LDAP_INIT_DIR/initialized
fi

# Unset sensitive variables
unset IDP_LDAP_ADMIN_PASSWORD
unset IDP_LDAP_IDPUSER_PASSWORD
unset IDP_LDAP_TESTUSER_PASSWORD

slapd -u ldap -g ldap -d 128