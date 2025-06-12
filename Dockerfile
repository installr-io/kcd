##
## BUILD STAGE
##
FROM redhat/ubi10:10.0 AS builder
ARG KEYCLOAK_CONFIG_CLI_VERSION
ARG KEYCLOAK_VERSION
ARG KEYCLOAK_CLIENT_VERSION
ARG KEYCLOAK_CONFIG_CLI_BUILD_PROFILE

## install build tools
RUN dnf -y install gzip patch maven

## build dir
WORKDIR /build

## download & unpack keycloak-config-cli
RUN curl -fssLO \
        https://github.com/adorsys/keycloak-config-cli/archive/refs/tags/v${KEYCLOAK_CONFIG_CLI_VERSION}.tar.gz
RUN tar -xzf v${KEYCLOAK_CONFIG_CLI_VERSION}.tar.gz

COPY .m2 /root/.m2

## apply patch & build
COPY deployer.patch .
RUN --mount=type=secret,id=GITHUB_ACTOR,env=GITHUB_ACTOR,required \
    --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required \
    set -e; \
    cd keycloak-config-cli-${KEYCLOAK_CONFIG_CLI_VERSION}; \
    patch -p1 < ../deployer.patch; \
    mvn clean package \
        -DskipTests \
        -Dkeycloak.version=${KEYCLOAK_VERSION} \
        -Dkeycloak.client.version=${KEYCLOAK_CLIENT_VERSION} \
        -P${KEYCLOAK_CONFIG_CLI_BUILD_PROFILE}

##
## PRODUCTION STAGE
##
FROM registry.access.redhat.com/ubi8/openjdk-21:1.20
LABEL org.opencontainers.image.source=https://github.com/installr-io/installr-kcd
ARG KEYCLOAK_CONFIG_CLI_VERSION

COPY --from=builder /build/keycloak-config-cli-${KEYCLOAK_CONFIG_CLI_VERSION}/target/keycloak-config-cli.jar \
    /deployments/

ENV JAVA_OPTS_APPEND="-Dspring.main.web-application-type=SERVLET"
ENV JAVA_APP_JAR="/deployments/keycloak-config-cli.jar"

ENTRYPOINT [ \
    "/opt/jboss/container/java/run/run-java.sh", \
    "--logging.level.root=${LOG_LEVEL:-warn}", \
    "--keycloak.ssl-verify=false", \
    "--keycloak.url=", \
    "--keycloak.user=", \
    "--keycloak.password=", \
    "--keycloak.availability-check.enabled=true", \
    "--keycloak.availability-check.timeout=30s", \
    "--keycloak.availability-check.retry-delay=2s", \
    "--import.files.locations=", \
    "--import.managed.authentication-flow=no-delete", \
    "--import.managed.identity-provider=no-delete", \
    "--import.managed.client=no-delete" \
]
