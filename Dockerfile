#FROM openjdk:8-jdk-slim
FROM argoproj/argocd
#FROM lachlanevenson/k8s-kubectl


ENV PORT 8090
ENV CLASSPATH /opt/lib
EXPOSE 8090
RUN wget --no-check-certificate --no-cookies --header "Cookie: oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jdk/8u141-b15/336fa29ff2bb4ef291e347e091f7f4a7/jdk-8u141-linux-x64.rpm
RUN sudo yum install -y jdk-8u141-linux-x64.rpm
# copy pom.xml and wildcards to avoid this command failing if there's no target/lib directory
COPY pom.xml target/lib* /opt/lib//

# NOTE we assume there's only 1 jar in the target dir
# but at least this means we don't have to guess the name
# we could do with a better way to know the name - or to always create an app.jar or something
COPY target/*.war /opt/app.war
WORKDIR /opt
CMD ["java", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseCGroupMemoryLimitForHeap", "-jar", "app.war"]
