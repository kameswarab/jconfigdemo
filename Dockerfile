#FROM openjdk:8-jdk-slim
FROM argoproj/argocd
#FROM lachlanevenson/k8s-kubectl


ENV PORT 8090
ENV CLASSPATH /opt/lib
EXPOSE 8090
RUN yum install -y \
       java-1.8.0-openjdk-1.8.0.242.b08-1.el7 \ 
       java-1.8.0-openjdk-devel-1.8.0.242.b08-1.el7 \ 
    && echo "securerandom.source=file:/dev/urandom" >> /usr/lib/jvm/jre/lib/security/java.security \
    && yum clean all

ENV JAVA_HOME /etc/alternatives/jre
# copy pom.xml and wildcards to avoid this command failing if there's no target/lib directory
COPY pom.xml target/lib* /opt/lib/

# NOTE we assume there's only 1 jar in the target dir
# but at least this means we don't have to guess the name
# we could do with a better way to know the name - or to always create an app.jar or something
COPY target/*.war /opt/app.war
WORKDIR /opt
CMD ["java", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseCGroupMemoryLimitForHeap", "-jar", "app.war"]
