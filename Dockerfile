FROM argoproj/argocd as argo
FROM lachlanevenson/k8s-kubectl as kube
FROM openjdk:8-jdk-slim
ENV PORT 8090
ENV CLASSPATH /opt/lib
EXPOSE 8090
COPY --from=argo  /usr/local/bin/argocd* /usr/local/bin/
COPY --from=argo  /shared/app /shared/app
COPY --from=kube  /usr/local/bin/kubectl* /usr/local/bin/

RUN chmod +x /usr/local/bin/kubectl
# copy pom.xml and wildcards to avoid this command failing if there's no target/lib directory
COPY pom.xml target/lib* /opt/lib/

# NOTE we assume there's only 1 jar in the target dir
# but at least this means we don't have to guess the name
# we could do with a better way to know the name - or to always create an app.jar or something
COPY target/*.war /opt/app.war
WORKDIR /opt
CMD ["java", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseCGroupMemoryLimitForHeap", "-jar", "app.war"]
