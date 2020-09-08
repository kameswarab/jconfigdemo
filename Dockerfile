ARG BASE_IMAGE=debian:10-slim
#####JAVA IMAHG####
FROM centos:7.7.1908 as javabase

USER root

RUN mkdir -p /deployments

# JAVA_APP_DIR is used by run-java.sh for finding the binaries
ENV JAVA_APP_DIR=/deployments \
    JAVA_MAJOR_VERSION=8


# /dev/urandom is used as random source, which is prefectly safe
# according to http://www.2uo.de/myths-about-urandom/
RUN yum install -y \
       java-1.8.0-openjdk-1.8.0.242.b08-1.el7 \ 
       java-1.8.0-openjdk-devel-1.8.0.242.b08-1.el7 \ 
    && echo "securerandom.source=file:/dev/urandom" >> /usr/lib/jvm/jre/lib/security/java.security \
    && yum clean all

ENV JAVA_HOME /etc/alternatives/jre
#####

####################################################################################################
# Builder image
# Initial stage which pulls prepares build dependencies and CLI tooling we need for our final image
# Also used as the image in CI jobs so needs all dependencies
####################################################################################################
FROM golang:1.14.1 as builder

RUN echo 'deb http://deb.debian.org/debian buster-backports main' >> /etc/apt/sources.list

RUN apt-get update && apt-get install -y \
    openssh-server \
    nginx \
    fcgiwrap \
    git \
    git-lfs \
    make \
    wget \
    gcc \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /tmp

ADD hack/install.sh .
ADD hack/installers installers
ADD hack/tool-versions.sh .

RUN ./install.sh packr-linux
RUN ./install.sh kubectl-linux
RUN ./install.sh ksonnet-linux
RUN ./install.sh helm2-linux
RUN ./install.sh helm-linux
RUN ./install.sh kustomize-linux

####################################################################################################
# Argo CD Base - used as the base for both the release and dev argocd images
####################################################################################################
FROM $BASE_IMAGE as argocd-base

USER root

RUN echo 'deb http://deb.debian.org/debian buster-backports main' >> /etc/apt/sources.list

RUN groupadd -g 999 argocd && \
    useradd -r -u 999 -g argocd argocd && \
    mkdir -p /home/argocd && \
    chown argocd:0 /home/argocd && \
    chmod g=u /home/argocd && \
    chmod g=u /etc/passwd && \
    apt-get update && \
    apt-get install -y git git-lfs python3-pip tini gpg && \
    apt-get clean && \
    pip3 install awscli==1.18.80 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY hack/git-ask-pass.sh /usr/local/bin/git-ask-pass.sh
COPY hack/gpg-wrapper.sh /usr/local/bin/gpg-wrapper.sh
COPY hack/git-verify-wrapper.sh /usr/local/bin/git-verify-wrapper.sh
COPY --from=builder /usr/local/bin/ks /usr/local/bin/ks
COPY --from=builder /usr/local/bin/helm2 /usr/local/bin/helm2
COPY --from=builder /usr/local/bin/helm /usr/local/bin/helm
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/bin/kustomize /usr/local/bin/kustomize
# script to add current (possibly arbitrary) user to /etc/passwd at runtime
# (if it's not already there, to be openshift friendly)
COPY uid_entrypoint.sh /usr/local/bin/uid_entrypoint.sh

# support for mounting configuration from a configmap
RUN mkdir -p /app/config/ssh && \
    touch /app/config/ssh/ssh_known_hosts && \
    ln -s /app/config/ssh/ssh_known_hosts /etc/ssh/ssh_known_hosts 

RUN mkdir -p /app/config/tls
RUN mkdir -p /app/config/gpg/source && \
    mkdir -p /app/config/gpg/keys && \
    chown argocd /app/config/gpg/keys && \
    chmod 0700 /app/config/gpg/keys

# workaround ksonnet issue https://github.com/ksonnet/ksonnet/issues/298
ENV USER=argocd

USER 999
WORKDIR /home/argocd

####################################################################################################
# Argo CD UI stage
####################################################################################################
FROM node:11.15.0 as argocd-ui

WORKDIR /src
ADD ["ui/package.json", "ui/yarn.lock", "./"]

RUN yarn install

ADD ["ui/", "."]

ARG ARGO_VERSION=latest
ENV ARGO_VERSION=$ARGO_VERSION
RUN NODE_ENV='production' yarn build

####################################################################################################
# Argo CD Build stage which performs the actual build of Argo CD binaries
####################################################################################################
FROM golang:1.14.1 as argocd-build

COPY --from=builder /usr/local/bin/packr /usr/local/bin/packr

WORKDIR /go/src/github.com/argoproj/argo-cd

COPY go.mod go.mod
COPY go.sum go.sum

RUN go mod download

# Perform the build
COPY . .
RUN make cli-local server controller repo-server argocd-util

ARG BUILD_ALL_CLIS=true
RUN if [ "$BUILD_ALL_CLIS" = "true" ] ; then \
    make CLI_NAME=argocd-darwin-amd64 GOOS=darwin cli-local && \
    make CLI_NAME=argocd-windows-amd64.exe GOOS=windows cli-local \
    ; fi

####################################################################################################
# Final image
####################################################################################################
FROM argocd-base
COPY --from=argocd-build /go/src/github.com/argoproj/argo-cd/dist/argocd* /usr/local/bin/
COPY --from=argocd-ui ./src/dist/app /shared/app
COPY --from=javabase  /usr/lib/jvm/* /usr/lib/jvm/
ENV JAVA_HOME /usr/lib/jvm/jre 
ENV PORT 8090
ENV CLASSPATH /opt/lib
EXPOSE 8090

# copy pom.xml and wildcards to avoid this command failing if there's no target/lib directory
COPY pom.xml target/lib* /opt/lib/

# NOTE we assume there's only 1 jar in the target dir
# but at least this means we don't have to guess the name
# we could do with a better way to know the name - or to always create an app.jar or something
COPY target/*.war /opt/app.war
WORKDIR /opt
CMD ["java", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseCGroupMemoryLimitForHeap", "-jar", "app.war"]
