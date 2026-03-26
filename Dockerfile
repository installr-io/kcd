##
## BUILD STAGE
##
FROM maven:3.9.11-eclipse-temurin-21-alpine AS builder
ARG KEYCLOAK_CONFIG_CLI_VERSION
ARG KEYCLOAK_VERSION
ARG KEYCLOAK_CLIENT_VERSION
ARG KEYCLOAK_CONFIG_CLI_BUILD_PROFILE

## install build tools
RUN apk add patch

## build dir
WORKDIR /build

## download & unpack keycloak-config-cli
RUN set -e; \
    curl -fssLO \
        https://github.com/adorsys/keycloak-config-cli/archive/refs/tags/v${KEYCLOAK_CONFIG_CLI_VERSION}.tar.gz; \
    tar -xzf v${KEYCLOAK_CONFIG_CLI_VERSION}.tar.gz

COPY .m2 /root/.m2

## apply patch & build
COPY deployer.patch .
RUN --mount=type=secret,id=GITHUB_ACTOR,env=GITHUB_ACTOR,required \
    --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required \
    set -e; \
    cd keycloak-config-cli-${KEYCLOAK_CONFIG_CLI_VERSION}; \
    patch -p1 < ../deployer.patch; \
    mvn -V clean package \
        -DskipTests \
        -Dkeycloak.version=${KEYCLOAK_VERSION} \
        -Dkeycloak.client.version=${KEYCLOAK_CLIENT_VERSION} \
        -P${KEYCLOAK_CONFIG_CLI_BUILD_PROFILE}

##
## PRODUCTION STAGE
##
FROM ghcr.io/installr-io/uci:jre21-1
LABEL org.opencontainers.image.source=https://github.com/installr-io/kcd
ARG KEYCLOAK_CONFIG_CLI_VERSION

COPY --from=builder /build/keycloak-config-cli-${KEYCLOAK_CONFIG_CLI_VERSION}/target/keycloak-config-cli.jar .

ENV UCI_JRE_CUSTOM_OPTS="-Dspring.main.web-application-type=SERVLET"

ENTRYPOINT [ \
    "bin/run-java", \
    "-jar", \
    "keycloak-config-cli.jar", \
    "--logging.level.root=${LOG_LEVEL:-warn}", \
    "--keycloak.ssl-verify=false", \
    "--keycloak.url=", \
    "--keycloak.user=", \
    "--keycloak.password=", \
    "--keycloak.availability-check.enabled=true", \
    "--keycloak.availability-check.timeout=60s", \
    "--keycloak.availability-check.retry-delay=2s", \
    "--import.files.locations=", \
    "--import.managed.authentication-flow=no-delete", \
    "--import.managed.identity-provider=no-delete", \
    "--import.managed.client=no-delete" \
]
