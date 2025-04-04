#!/bin/sh

# rebuild idp war file to incorporate any post-install additions
/opt/shibboleth-idp/bin/build.sh

# launch supervisord
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf