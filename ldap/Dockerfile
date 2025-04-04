FROM almalinux:9.5-minimal

ENV LDAP_DATA_DIR="/var/lib/ldap" \
    LDAP_BASE_DIR="/etc/openldap" \
    LDAP_CONFIG_DIR="/etc/openldap/slapd.d" \
    LDAP_SCHEMA_DIR="/etc/openldap/schema" \ 
    LDAP_INIT_DIR="/etc/openldap/init"

# Install OpenLDAP
RUN rm -fr /var/cache/dnf/* && microdnf clean all && microdnf -y update && \
    microdnf -y install --setopt=tsflags=nodocs epel-release && \
    microdnf -y install openldap openldap-servers openldap-clients gettext && \
    microdnf -y clean all && \
    rm -rf /var/cache/dnf

# OpenLDAP default config
COPY install/init/* ${LDAP_INIT_DIR}/

RUN rm -rf ${LDAP_CONFIG_DIR}/* && \
    rm -rf ${LDAP_DATA_DIR}/* && \
    mkdir -p ${LDAP_DATA_DIR} ${LDAP_CONFIG_DIR} && \
    chown -R ldap:ldap ${LDAP_DATA_DIR} ${LDAP_BASE_DIR} && \
    chmod -R 750 ${LDAP_DATA_DIR} ${LDAP_BASE_DIR}

# Import LDAP Schema
COPY install/schema/* ${LDAP_SCHEMA_DIR}/
COPY install/importSchema.sh ${LDAP_BASE_DIR}
RUN chmod +x ${LDAP_BASE_DIR}/importSchema.sh

# Ports
EXPOSE 389

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]

# Switch to ldap user
USER ldap