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
FROM argoproj/argocd
COPY --from=javabase /etc/alternatives/jre/* /etc/alternatives/jre/
ENV JAVA_HOME /etc/alternatives/jre 
ENV PATH $PATH:$JAVA_HOME/bin
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
