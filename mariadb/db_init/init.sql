SET NAMES 'utf8';
SET CHARACTER SET utf8;
CHARSET utf8;
CREATE DATABASE IF NOT EXISTS shibboleth CHARACTER SET=utf8;
USE shibboleth;

CREATE TABLE IF NOT EXISTS StorageRecords (
  context varchar(255) NOT NULL,
  id varchar(255) NOT NULL,
  expires bigint(20) DEFAULT NULL,
  value longtext NOT NULL,
  version bigint(20) NOT NULL,
  PRIMARY KEY (context, id)
) COLLATE utf8_bin;

CREATE TABLE IF NOT EXISTS shibpid (
    localEntity VARCHAR(255) NOT NULL,
    peerEntity VARCHAR(255) NOT NULL,
    persistentId VARCHAR(255) NOT NULL,
    principalName VARCHAR(255) NOT NULL,
    localId VARCHAR(255) NOT NULL,
    peerProvidedId VARCHAR(255) NULL,
    creationDate TIMESTAMP NOT NULL,
    deactivationDate TIMESTAMP NULL,
    PRIMARY KEY (localEntity, peerEntity, persistentId)
);
-- TODO: Initial configuration of password
CREATE USER 'shibboleth'@'localhost' IDENTIFIED BY 'shibboleth';

GRANT ALL PRIVILEGES ON shibboleth.* TO 'shibboleth'@'localhost';

FLUSH PRIVILEGES;