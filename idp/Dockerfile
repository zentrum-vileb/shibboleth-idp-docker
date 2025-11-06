######################################
# PLATFORM
######################################
FROM almalinux:9-minimal AS shibidp_base

######################################
# VERSION SETTINGS
######################################
ENV TOMCAT_MAJOR=10 \
    TOMCAT_VERSION=10.1.48 \
    IDP_VERSION=5.1.6 \
    JAKARTA_JSTL_VERSION=3.0.1 \
    JAKARTA_JSTL_API_VERSION=3.0.2

######################################
# ARGUMENTS
######################################
# Match with host user (set in .env)
ARG CONTAINER_UID=1000
ARG CONTAINER_GID=1000

# Internal user
ARG USER_NAME=tomcat
ARG USER_GROUPNAME=tomcat

# Configuration
# [1] Burned-In: Copy config files 
# [2] Run-time: Mount config paths [x]
ARG TOMCFG=config/tomcat
ARG TOMCERT=credentials/tomcat
ARG TOMWWWROOT=wwwroot
ARG SHBCFG=config/shib-idp/conf
ARG SHBCREDS=credentials/shib-idp
ARG SHBVIEWSconfig/shib-idp/views
ARG SHBEDWAPP=config/shib-idp/edit-webapp
ARG SHBMSGS=config/shib-idp/messages
ARG SHBMD=config/shib-idp/metadata
ARG SHBINSTALL=config/install
# [3] Hybrid: Docker secrets
#COPY ${TOMCFG} /opt/tomcat/conf
#COPY ${TOMCERT} /opt/certs
#COPY ${TOMWWWROOT} /opt/tomcat/webapps/ROOT
#COPY ${SHBCFG} /opt/shibboleth-idp/conf
#COPY ${SHBCREDS} /opt/shibboleth-idp/credentials
#COPY ${SHBVIEWS} /opt/shibboleth-idp/views
#COPY ${SHBEDWAPP} /opt/shibboleth-idp/edit-webapp
#COPY ${SHBMSGS} /opt/shibboleth-idp/messages
#COPY ${SHBMD} /opt/shibboleth-idp/metadata
#COPY ${SHBINSTALL} /opt/install

######################################
# OTHER VARS 
######################################
ENV IMAGENAME=shibidp
# java
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV JAVA_OPTS='-Xmx3000m'
# tomcat
ENV CATALINA_HOME=/opt/tomcat
ENV TOMCAT_TGZ_URL=https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
    PATH=$CATALINA_HOME/bin:$JAVA_HOME/bin:$PATH
# idp
ENV SHIB_RELDIR=https://shibboleth.net/downloads/identity-provider/archive/$IDP_VERSION \
    SHIB_PREFIX=shibboleth-identity-provider-$IDP_VERSION

# Shibboleth Library path within the container
#ENV LIB_PATH=/opt/shibboleth-idp/edit-webapp/WEB-INF/lib/
ENV LIB_PATH=/opt/tomcat/lib/

# Labels
LABEL Vendor="NoVendor" \
      ImageType="Shibboleth IDP" \
      ImageName=$IMAGENAME \
      ImageOS=AlmaLinux9-Minimal \
      Version=$IDP_VERSION

#######################################
# BEGIN IMAGE BUILD
#######################################

######################################
# ALMALINUX 9 Minimal - Dependencies
######################################
RUN rm -fr /var/cache/dnf/* && microdnf clean all && microdnf -y update && microdnf -y install --setopt=tsflags=nodocs epel-release && \
    microdnf -y install tar openssl supervisor && \
    microdnf -y clean all && \
    rm -rf /var/cache/dnf

######################################
# OpenJDK 17
######################################
RUN microdnf install -y java-17-openjdk && \
    ln -sfn /usr/lib/jvm/java-17-openjdk-* /usr/lib/jvm/java-17-openjdk

######################################
# IDENTITY PROVIDER
######################################
# Copy IdP installer files
ADD install/idp/idp.installer.properties install/idp/idp.merge.properties install/idp/ldap.merge.properties /tmp/
		   
# Install IdP
RUN mkdir -p /tmp/shibboleth && cd /tmp/shibboleth && \
    curl -sO https://shibboleth.net/downloads/PGP_KEYS && \
    curl -sO $SHIB_RELDIR/$SHIB_PREFIX.tar.gz && \
    curl -sO $SHIB_RELDIR/$SHIB_PREFIX.tar.gz.asc && \
# Verifiy signature
    gpg --import PGP_KEYS && \
    gpg --batch --verify $SHIB_PREFIX.tar.gz.asc $SHIB_PREFIX.tar.gz && \
# Untar
    tar xf $SHIB_PREFIX.tar.gz && \
# Install
    ln -s /tmp/shibboleth/${SHIB_PREFIX} /tmp/shibboleth/idp && \
    cd /tmp/shibboleth/$SHIB_PREFIX && \
    ./bin/install.sh \
        --noPrompt true \
      	--propertyFile /tmp/idp.installer.properties && \
# Cleanup
    cd ~ && \
    rm -rf /tmp/shibboleth

######################################
# TOMCAT
######################################
RUN mkdir -p "$CATALINA_HOME" && set -x \
        && curl -s -o $CATALINA_HOME/tomcat.tar.gz "$TOMCAT_TGZ_URL" \
        && curl -s -o $CATALINA_HOME/tomcat.tar.gz.asc "$TOMCAT_TGZ_URL.asc" \
        && curl -s -L -o $CATALINA_HOME/KEYS "https://downloads.apache.org/tomcat/tomcat-$TOMCAT_MAJOR/KEYS" \
        && gpg --import $CATALINA_HOME/KEYS \
        && gpg $CATALINA_HOME/tomcat.tar.gz.asc \
	&& gpg --batch --verify $CATALINA_HOME/tomcat.tar.gz.asc $CATALINA_HOME/tomcat.tar.gz \
	&& tar -xvf $CATALINA_HOME/tomcat.tar.gz -C $CATALINA_HOME --strip-components=1 \
	&& rm $CATALINA_HOME/bin/*.bat \
	&& rm $CATALINA_HOME/tomcat.tar.gz*
RUN mkdir -p $CATALINA_HOME/conf/Catalina \
    mkdir -p $CATALINA_HOME/webapps/ROOT \
	&& ln -s /opt/shibboleth-idp/war/idp.war $CATALINA_HOME/webapps/idp.war

# Temporary initial config (will be provided on startup, e.g. via volume mount)
ADD install/idp/idp.xml $CATALINA_HOME/conf/Catalina/idp.xml
ADD install/tomcat/server.xml $CATALINA_HOME/conf/server.xml

######################################
# DEPENDENCIES: JSTL & Nashorn
######################################

# JSTL
## JSTL from local
#ADD install/tomcat/jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar $LIB_PATH
#ADD install/tomcat/jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar $LIB_PATH

## JSTL from Repo
RUN mkdir -p $LIB_PATH \ 
        && rm -f $LIB_PATH/jakarta.servlet.jsp.jstl*.jar \
        && cd $LIB_PATH \ 
        && curl -s -O  "https://repo.maven.apache.org/maven2/org/glassfish/web/jakarta.servlet.jsp.jstl/$JAKARTA_JSTL_VERSION/jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar" \ 
        && curl -s -O  "https://repo.maven.apache.org/maven2/org/glassfish/web/jakarta.servlet.jsp.jstl/$JAKARTA_JSTL_VERSION/jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar.sha1" \ 
        && echo "$(cat jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar.sha1) jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar" > "jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar.sha1" \
        && sha1sum -c "jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar.sha1" \
        #&& curl -s -O  "https://repo.maven.apache.org/maven2/org/glassfish/web/jakarta.servlet.jsp.jstl/$JAKARTA_JSTL_VERSION/jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar.asc" \ 
        #&& gpg --batch --verify "$LIB_PATH/jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar.asc" "$LIB_PATH/jakarta.servlet.jsp.jstl-$JAKARTA_JSTL_VERSION.jar" \
        && curl -s -O "https://repo.maven.apache.org/maven2/jakarta/servlet/jsp/jstl/jakarta.servlet.jsp.jstl-api/$JAKARTA_JSTL_API_VERSION/jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar" \
        && curl -s -O "https://repo.maven.apache.org/maven2/jakarta/servlet/jsp/jstl/jakarta.servlet.jsp.jstl-api/$JAKARTA_JSTL_API_VERSION/jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar.sha1" \
        && echo "$(cat jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar.sha1) jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar" > "jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar.sha1" \
        && sha1sum -c "jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar.sha1" \
        #&& curl -s -O "https://repo.maven.apache.org/maven2/jakarta/servlet/jsp/jstl/jakarta.servlet.jsp.jstl-api/$JAKARTA_JSTL_API_VERSION/jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar.asc" \
        #&& gpg --batch --verify "$LIB_PATH/jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar.asc" "$LIB_PATH/jakarta.servlet.jsp.jstl-api-$JAKARTA_JSTL_API_VERSION.jar" \
        #&& rm -f $LIB_PATH/*.asc \
        && rm -f $LIB_PATH/jakarta.servlet.jsp.jstl*.sha1

# NASHORN
ARG truststore="/opt/shibboleth-idp/credentials/PGP_KEYS"
ARG plugin_args="--noPrompt --noRebuild --truststore ${truststore}"
RUN /bin/curl -Lo ${truststore} https://shibboleth.net/downloads/PGP_KEYS && \
    /opt/shibboleth-idp/bin/plugin.sh ${plugin_args} -I net.shibboleth.idp.plugin.nashorn

########################
# IDP plugins
########################

# Shibboleth Consent
RUN /opt/shibboleth-idp/bin/module.sh -t idp.intercept.Consent || /opt/shibboleth-idp/bin/module.sh -e idp.intercept.Consent

######################################
# DATABASE: Storage JDBC
######################################
RUN /opt/shibboleth-idp/bin/plugin.sh ${plugin_args} -I net.shibboleth.plugin.storage.jdbc

######################################
# DATABASE: MariaDB Java Connector
######################################
# Repo: https://dlm.mariadb.com/browse/java8_connector/316/2100/
# (Env only needed if not installed from packages)
ENV MARIADB_JDBC_VERSION=3.5.1
ENV MARIADB_JDBC_DRIVER="https://dlm.mariadb.com/3978472/Connectors/java/connector-java-$MARIADB_JDBC_VERSION/mariadb-java-client-$MARIADB_JDBC_VERSION.jar"
ENV MARIADB_JDBC_DRIVER_ASC="https://dlm.mariadb.com/3978461/Connectors/java/connector-java-$MARIADB_JDBC_VERSION/mariadb-java-client-$MARIADB_JDBC_VERSION.jar.asc"

# MariaDB Connector from packages
RUN microdnf install -y mariadb-java-client \
        && ln -s /usr/lib/java/mariadb-java-client.jar $CATALINA_HOME/lib/mariadb-java-client.jar

# MariaDB Connector from external sources
#RUN cd $CATALINA_HOME/lib \
        #&& wget -q "$MARIADB_JDBC_DRIVER"  \
        #&& wget -q "$MARIADB_JDBC_DRIVER_ASC" \
        #&& curl -s -o "$CATALINA_HOME/KEYS_MARIADB" "https://supplychain.mariadb.com/MariaDB-Server-GPG-KEY" \
        #&& gpg --import "$CATALINA_HOME/KEYS_MARIADB" \
        #&& gpg --batch --verify "$CATALINA_HOME/mariadb-java-client-$MARIADB_JDBC_VERSION.jar.asc" "$CATALINA_HOME/lib/mariadb-java-client-$MARIADB_JDBC_VERSION.jar" \
        #&& rm $CATALINA_HOME/lib/mariadb-java-client-$MARIADB_JDBC_VERSION.jar.asc

######################################
# SCRIPTS
######################################
# Env and startup
ADD install/tomcat/setenv.sh $CATALINA_HOME/bin/
ADD install/system/startup.sh /usr/bin/

# Supervisor
ADD install/system/supervisord.conf /etc/supervisor/supervisord.conf
RUN mkdir -p /etc/supervisor/conf.d \
        && chmod +x /usr/bin/startup.sh

# Fix line endings (CRLF - LF)
#RUN sed -i 's/\r$//' /usr/bin/startup.sh

########################
# CLEANUP
########################

## Remove the default webapps
RUN rm -rf $CATALINA_HOME/webapps/docs $CATALINA_HOME/webapps/examples $CATALINA_HOME/webapps/host-manager

# Microdnf
RUN microdnf -y clean all \ 
        && rm -rf /var/cache/dnf

######################################
# USER AND PERMISSIONS
######################################
RUN groupadd -g ${CONTAINER_GID} ${USER_GROUPNAME} && \
    useradd -u ${CONTAINER_UID} -g ${USER_GROUPNAME} ${USER_NAME}

## Shibboleth permisisons
RUN chown -R ${CONTAINER_UID} /opt/tomcat \
        && chown -R ${CONTAINER_UID} /opt/shibboleth-idp/* \
        && chown -R ${CONTAINER_UID} /opt/shibboleth-idp/ 

## Supervisord
RUN mkdir -p /var/run/supervisor /var/log/supervisor /etc/supervisor \
    && chown -R ${CONTAINER_UID} /var/run/supervisor /var/log/supervisor /etc/supervisor

RUN chown -R ${CONTAINER_UID} /var/run

USER ${CONTAINER_UID}

######################################
# CONTAINER HEALTH
######################################
HEALTHCHECK --interval=5m --timeout=30s \
   CMD curl -k -s -f http://127.0.0.1:8080/idp/status || exit 1

######################################
# CONTAINER STARTUP
######################################
CMD ["/usr/bin/startup.sh"]


