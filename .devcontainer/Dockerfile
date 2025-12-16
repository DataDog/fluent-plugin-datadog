FROM fluent/fluentd:latest

ENV DEBIAN_FRONTEND=noninteractive
USER root

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl

WORKDIR /workspaces

