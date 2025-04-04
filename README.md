# Shibboleth IDP v5
This is an experimental setup for demo purposes. 
It's not intended for direct use in production.
We cannot provide any support or warranty. 
This repository is not maintained.

# Docker

## Requirements

### Host
- Time synchronsation on host (NTP/PTP service or similar running on host)
  - e.g. ntp, chrony
- Reverse proxy setup (incl. SSL), e.g. Apache or Nginx 
  [or integrate here]

## Dockerfile

## Docker Compose
You can set the compose file within the `.env`

`docker-compose.ext.yml`
- Non-IDP services run on host/external, e.g. shibboleth sql, ldap
- Might also be used temporarily for migration purposes from IDPv4 to IDPv5

`docker-compose.yml`
- Dockerized services in containers, incl. shibboleth sql, ldap

# Environement
Setup your environement

1. New configuration?
    ```sh
    cp ./.env.example ./.env
    ```

2. Adjust settings in `.env`

# Permissions

## Scripts
Set permissions on host.

1. Make scripts executable
    ```sh
    chmod +x ./compose.sh ./scripts/functions.sh
    ```

2. Init config and update permissions for mounted folders

- Init config, creates user and group, updates permissions
    ```sh
    sh compose.sh update --config
    ```

- Create or use a user on host (see .env) and set permissions for mounted folders, e.g. run script to add user/group and update permissions:
    ```sh
    sh compose.sh update --permissions
    ```

Note
- The warning ```getent: command not found``` can be ignored in some contexts, e.g. dev build machines (e.g. git bash shell / WSL), should work with default user


3. Start the containers, e.g.

    ```sh
    docker compose up
    ```

    ```sh
    sh compose.sh up 
    ```

## Build

## Certificates
This example uses:
- Self signed certificates 
  - for SAML communication
  - for backchannel communication (e.g. Attribute Query)
- Validation of metadata (DFN-AAI)
  - MDQ: [`dfn-aai-mdq.pem`](https://doku.tid.dfn.de/de:aai:mdq)
  - IDP: [`dfn-aai.pem`](https://doku.tid.dfn.de/de:metadata)

## Mounted folders
- See `docker-compose*.yml`

## Ports

Default ports *within* the containers:
- tomcat ajp: 8009
- tomcat http: 8080
- sql (mariadb): 3306
- ldap(s): 389

Not part of this setup:
- reverse proxy (e.g. apache): 80 / 443 / 8443

# Migration from existing IDPv4
To use external services (sql, ldap), e.g. on docker host or different servers, ensure that these can be access from the container (e.g. ip rules)

## Shibboleth SQL
- Convert character sets, set new collation, e.g.
    ```
    ALTER TABLE StorageRecords CONVERT TO CHARACTER SET utf8 COLLATE utf8_bin;
    ```
    (see also: [DFN-WIKI](https://doku.tid.dfn.de/de:shibidp:installation_jdbc-plugin_und_nashorn-plugin))

  - Conversion adresses the warning of `JDBCStorageService`
    > [WARN] : net.shibboleth.shared.spring.context.DelimiterAwareApplicationContext: Exception encountered during context initialization - cancelling refresh attempt: org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'JDBCStorageService' defined in file [/opt/shibboleth-idp/conf/global.xml]: net.shibboleth.shared.component.ComponentInitializationException: Key Column is Case Insensitive

## LDAP
- Using an external LDAP: Ensure that the ldap server can be accessed from the container

# Management
Ports depend on .env

## IDP
via Tomcat HTTP, for development/testing purposes:
- IDP-Status:
  - http://localhost:8081/idp/status
- Resolvertest with test user:
  - e.g. http://localhost:8081/idp/profile/admin/resolvertest?requester=https://your-staging-sp.example.org/shibboleth&principal=max&saml2

*or*

via Reverse Proxy:
- IDP-Status: 
  - https://idp.example.org/idp/status
- Resolvertest: 
  - https://idp.example.org/idp/profile/admin/resolvertest?requester=[ENTITY-ID]&principal=[USER-ID]&saml2

## Tomcat
Tomcat Manager for development/testing purposes:
- URL: http://localhost:8081/manager/
- Credentials: admin - changeme (see .env)

## MariaDB (SQL)
via phpmyadmin for development/testing purposes of the shibboleth sql database
- URL: http://localhost:8082/
- Credentials: root - root

## LDAP
via phpldapadmin for development/testing purposes of the ldap database
- URL: http://localhost:8083/

## Reload services
- e.g. Attribute Resolver:
  - https://idp.example.org/idp/profile/admin/reload-service?id=shibboleth.AttributeResolverService

# Scripts

## Shibboleth Identity Provider
You can use the default docker compose commands to run the container.
Alternatively you can use the script to run and manage the container.

### Script
`compose.sh`
```
sh compose.sh (args) (option, e.g. [start | up (--build)])
```

ARGUMENTS (args) [optional]
```
  -b = backup services (mariadb, ldap)
```

OPTION (option)
```
  start     ~= docker compose start
  restart   ~= docker compose restart

  up (--*)  ~= docker compose up (--*)
    --build = build images before starting containers

  stop      ~= docker compose stop
  down (--*) ~= docker compose down (--*)
     --rmi = remove images
     --v / --volumes = remove volumes
  
  update --*
    --config = update configuration
    --saml-metadata = update saml metadata certificates
    --new-saml-cert = generate new self signed certificate
    --rollover-saml-cert = rollover self signed certificates
    --war = rebuild idp war
    --creds = update credentials (dfn metadata certificate, shibboleth pgp keys) and schema (dfn attribute schema)
```

### Example usage
initialize configuration and (re-)build images and containers:
```sh
sh compose.sh up --build
```

backup services and start containers:
```sh
sh compose.sh -b start 
```

### Rebuild war

```sh
sh compose.sh update --war
```

## Known issues

### Shibboleth
"Bean is not eligible for getting processed by all BeanPostProcessors"
- see: [Release Notes of Shibboleth IDP 5](https://shibboleth.atlassian.net/wiki/spaces/IDP5/pages/3199500367/ReleaseNotes#Known-Issues) | [Jira: IDP-2288](https://shibboleth.atlassian.net/browse/IDP-2288)
  > WARN [org.springframework.context.support.PostProcessorRegistrationDelegate$BeanPostProcessorChecker:437] - Bean 'net.shibboleth.idp.saml.attribute.impl.AttributeMappingNodeProcessor#0' of type [net.shibboleth.idp.saml.attribute.impl.AttributeMappingNodeProcessor] is not eligible for getting processed by all BeanPostProcessors (for example: not eligible for auto-proxying). Is this bean getting eagerly injected into a currently created BeanPostProcessor [net.shibboleth.spring.metadata.NodeProcessingAttachingBeanPostProcessor#0]? Check the corresponding BeanPostProcessor declaration and its dependencies.

### Tomcat
"At least one JAR was scanned for TLDs yet contained no TLDs"
- set `org.apache.catalina.startup.TldConfig.jarsToSkip=*.jar` in `catalina.properties` to skip jars
  > INFO [main] org.apache.jasper.servlet.TldScanner.scanJars At least one JAR was scanned for TLDs yet contained no TLDs. Enable debug logging for this logger for a complete list of JARs that were scanned but no TLDs were found in them. Skipping unneeded JARs during scanning can improve startup time and JSP compilation time.

### Docker
- The missing env variable message can be ignored:
  > level=warning msg="The \"resolutionContext\" variable is not set. Defaulting to a blank string."
- If you receive "no such file" errors for scripts on container startup, check file line endings, e.g. if you built on windows/wsl (should be linux file endings LF instead of CRLF); rebuild images after clearning built cache
  ```sh
  docker builder prune
  docker compose up
  ```
# Sources

Sources for documentation and/or docker images of shibboleth idp that might be of interest and from which inspiration was drawn.

## Documentation

**DFN AAI Wiki**
- https://doku.tid.dfn.de/de:shibidp:install

**ACOnet Wiki**
- https://wiki.univie.ac.at/display/federation/Shibboleth+IDP+5

**Australian Access Federation**
- https://github.com/ausaccessfed/shibboleth-idp5-installer

**SWITCHaai**
- https://help.switch.ch/aai/guides/idp/

## Docker

**TIER Incommon internet2**
- https://github.internet2.edu/docker/shib-idp

**ZIB (Zuse Institute Berlin)**
- https://git.zib.de/tweiss/shibboleth-idp/

**Ian Young**
- https://github.com/iay/shibboleth-idp-docker

