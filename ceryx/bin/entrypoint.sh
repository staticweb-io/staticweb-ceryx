#! /bin/bash

set -ex

if [ $CERYX_DEBUG == "true" ]
  then
    export CERYX_LOG_LEVEL=debug
  else
    export CERYX_LOG_LEVEL=info
fi

# Use Dockerize for templates and to wait for Redis
/usr/local/bin/dockerize \
    ${CERYX_DOCKERIZE_EXTRA_ARGS} \
    -template /usr/local/openresty/nginx/conf/nginx.conf.tmpl:/usr/local/openresty/nginx/conf/nginx.conf \
    -template  /usr/local/openresty/nginx/conf/ceryx.conf.tmpl:/usr/local/openresty/nginx/conf/ceryx.conf

# Execute subcommand
exec "$@"
