#!/bin/sh

# Import functions
source ./scripts/functions.sh

# Variables
SUBSTITUTE_VARIABLES=false
options=""

# Evaluate arguments
while getopts ":b" opt; do
  case ${opt} in
    b )
      DO_BACKUP=true
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      ;;
  esac
done
shift $((OPTIND -1))

###########################################
# Backup
###########################################
# Create backups with -b
if [ "$DO_BACKUP" = true ]; then
  backupServices
fi

###########################################
# Configuration
###########################################
if [ ! -d "$IDP_HOST_PATH_CONTAINER_FILES" ]; then
  read -r -p "No configuration files found. Do you want to initialize default config? [y/N] " DO_CONTINUE_INIT_CONFIG
  if [[ "$DO_CONTINUE_INIT_CONFIG" =~ ^([yY])+$ ]]; then
    initConfig
  else
    exit 1
  fi
fi

# Hot update and reload configuration
if [[ " $@ " =~ " update " ]]; then
  echo "Reloading configuration..."

  # Get the latest metadata certificate
  if [[ " $@ " =~ " --creds " ]]; then
    updateDfnSchema
    updateDfnMetadataCertificate
    updateShibbolethPgpKeys
  fi

  # Get the latest metadata certificate
  if [[ " $@ " =~ " --config " ]]; then
    updateConfig
  fi

  # Update permissions
  if [[ " $@ " =~ " --permissions " ]]; then
    updatePermissions
  fi

  # Get the latest metadata certificate
  if [[ " $@ " =~ " --saml-metadata " ]]; then
    updateSamlMetadata
  fi

  # Generate new self signed certificate "next"
  if [[ " $@ " =~ " --new-saml-cert " ]]; then
    generateSelfSignedCertificate
  fi

  # Rollover "next to "current" certificate 
  # Only use after new metadata has been published for 24 hours at least
  if [[ " $@ " =~ " --rollover-saml-cert " ]]; then
    rolloverSelfSignedCertificates
  fi

  # Rebuild the war
  if [[ " $@ " =~ " --war " ]]; then
    rebuildWar
  fi

  # Restart
  restartIDPContainer
fi

###########################################
# DOCKER COMPOSE COMMANDS
###########################################
if [[ " $@ " =~ " start " ]]; then
  docker compose start
  exit 1
fi

if [[ " $@ " =~ " restart " ]]; then
  docker compose restart
  exit 1
fi

if [[ " $@ " =~ " stop " ]]; then
  docker compose -f "$COMPOSE_FILE" stop
  exit 1
fi

if [[ " $@ " =~ " down " ]]; then
  read -r -p "Are you sure you want to shut down and remove containers? [y/N] " DO_SHUTDOWN
  if [[ "$DO_SHUTDOWN" =~ ^([yY])+$ ]]; then
    options=""
    if [[ " $@ " =~ " --rmi " ]]; then
      read -r -p "Are you sure you want to remove the images as well ? [y/N] " DO_DELETE_IMAGES
      if [[ "$DO_DELETE_IMAGES" =~ ^([yY])+$ ]]; then
        options="$options --rmi local" # Remove the idp image TODO
      fi
    fi

    if [[ " $@ " =~ " --volumes " || " $@ " =~ " --v " ]]; then
      read -r -p "WARNING: Are you sure you want to remove the volumes as well (DATA LOSS!)? [y/N] " DO_DELETE_VOLUMES

      # Backup services
      backupServices

      if [[ "$DO_DELETE_VOLUMES" =~ ^([yY])+$ ]]; then
        options="$options --volumes"
      fi
    fi

    echo "Shutting down and removing..."

    docker compose -f "$COMPOSE_FILE" down $options
    echo "Terminated."
    exit 0

  else
    echo "Aborted."
    exit 1
  fi
fi

# built the image 
# // docker buildx build idp/base_image (not in use)
if [[ " $@ " =~ " up " ]]; then
  if [[ " $@ " =~ " --build " ]]; then
    options="$options --build"
  fi
  docker compose up -d $options
  exit 1
fi

# cleanup
if [[ " $@ " =~ " cleanup " ]]; then
  docker builder prune
  #docker system prune --all
fi

echo "Finished."
exit 1
###########################################