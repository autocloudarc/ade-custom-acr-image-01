# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

ARG BASE_IMAGE=mcr.microsoft.com/deployment-environments/runners/core
ARG IMAGE_VERSION=latest

FROM ${BASE_IMAGE}:${IMAGE_VERSION}
WORKDIR /

ARG IMAGE_VERSION

# Metadata as defined at http://label-schema.org
ARG BUILD_DATE

# install terraform (latest version)
RUN set -eux; \
    ARCH="$(uname -m)"; case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) echo "Unsupported arch: $ARCH"; exit 1 ;; esac; \
    LATEST="$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"; \
    wget -O terraform.zip "https://releases.hashicorp.com/terraform/${LATEST}/terraform_${LATEST}_linux_${ARCH}.zip"; \
    unzip terraform.zip; rm terraform.zip; \
    mv terraform /usr/bin/terraform

# task-item: remove comments below after
# Grab all .sh files from scripts, copy to
# root scripts, replace line-endings and make them all executable
# COPY scripts/* /scripts/
# RUN find /scripts/ -type f -iname "*.sh" -exec dos2unix '{}' '+'
# RUN find /scripts/ -type f -iname "*.sh" -exec chmod +x {} \;

COPY --chmod=0755 scripts/*.sh /scripts/
RUN find /scripts/ -type f -iname "*.sh" -exec dos2unix '{}' '+'
