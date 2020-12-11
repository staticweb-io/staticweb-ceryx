#!/bin/sh
docker run -p 5000:5000 --restart always \
-e "REGISTRY_STORAGE=s3" \
-e "REGISTRY_STORAGE_S3_REGION=us-west-2" \
-e "REGISTRY_STORAGE_S3_BUCKET=staticweb-global-infra-repositorybucket-1quksgr5tcs6n" \
-e "REGISTRY_STORAGE_S3_ACCESSKEY=$AWS_ACCESS_KEY_ID" \
-e "REGISTRY_STORAGE_S3_SECRETKEY=$AWS_SECRET_ACCESS_KEY" \
-e "REGISTRY_STORAGE_CACHE_BLOBDESCRIPTOR=inmemory" \
registry:2
