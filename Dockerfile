ARG ELASTIC_VERSION=7.6.1
# This Dockerfile is based on <https://github.com/elastic/elasticsearch-docker>
FROM container-registry.oracle.com/os/oraclelinux:7-slim as builder

LABEL maintainer = "Verrazzano developers <verrazzano_ww@oracle.com>"

RUN set -eux; \
	yum install -y \
		wget \
		unzip \
		tar \
		gzip \
	; \
	rm -rf /var/cache/yum

# Default to UTF-8 file.encoding
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8
ENV ES_BUNDLED_JDK false
ENV ES_JAVA_OPTS "-Des.bundled_jdk=false"

# Environment variables for the builder image.
# Required to validate that you are using the correct file

ENV	JAVA_HOME=/usr/java
ENV PATH $JAVA_HOME/bin:$PATH
ARG GRAALVM_BINARY="${GRAALVM_BINARY:-graalvm-ee-java11-linux-amd64-20.1.0.1.tar.gz}"
COPY ${GRAALVM_BINARY} graalvm.tar.gz

ENV GRADLE_HOME=/opt/gradle \
	GRADLE_VERSION=6.2.2 \
	GRADLE_DOWNLOAD_SHA256=0f6ba231b986276d8221d7a870b4d98e0df76e6daf1f42e7c0baec5032fb7d17 \
	GRAALVM_DOWNLOAD_SHA256=870e51d13e7f42df50097110b14715e765e2a726aa2609c099872995c4409d8f

RUN set -eux; \
    echo "Checking GraalVM hash" ; \
    echo "${GRAALVM_DOWNLOAD_SHA256} *graalvm.tar.gz" | sha256sum --check -  ; \
    echo "Installing GraalVM"  ; \
    mkdir -p "$JAVA_HOME"; \
    tar xzf graalvm.tar.gz --directory "${JAVA_HOME}" --strip-components=1 ; \
    rm -f graalvm.tar.gz ; \
    echo "Testing GraalVM installation" ; \
    # -Xshare:dump will create a CDS archive to improve startup in subsequent runs
    java -Xshare:dump; \
    java --version; \
    javac --version; \
	echo "Downloading Gradle" ; \
	wget --no-verbose --output-document=gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" ; \
    echo "Checking download hash" ; \
	echo "${GRADLE_DOWNLOAD_SHA256} *gradle.zip" | sha256sum --check -  ; \
	echo "Installing Gradle"  ; \
	unzip gradle.zip  ; \
	rm -f gradle.zip ; \
	mv "gradle-${GRADLE_VERSION}" "${GRADLE_HOME}/" ; \
	ln --symbolic "${GRADLE_HOME}/bin/gradle" /usr/bin/gradle ; \
	echo "Testing Gradle installation" ; \
	gradle --version ; \
    echo "Adding gradle user and group" ; \
    groupadd --system --gid 1000 gradle  ; \
    useradd --system --gid gradle --uid 1000 --shell /bin/bash --create-home gradle ; \
    mkdir /home/gradle/.gradle ; \
    chown --recursive gradle:gradle /home/gradle ; \
    echo "Symlinking root Gradle cache to gradle Gradle cache" ; \
    ln -s /home/gradle/.gradle /root/.gradle ;

ENV ELASTIC_VERSION="7.6.1"
WORKDIR /home/gradle
COPY . .
RUN set -eux; \
    rm -f graalvm*.tar.gz; \
    gradle clean \
    :distribution:archives:oss-linux-tar:assemble \
    :plugins:analysis-phonetic:assemble \
    :plugins:mapper-size:assemble

# unzip in the build stage; tar/zip is not available by default in OL7 slim
RUN set -eux; \
    mkdir /usr/share/elasticsearch ; \
    tar -xzf "distribution/archives/oss-linux-tar/build/distributions/elasticsearch-oss-${ELASTIC_VERSION}-linux-x86_64.tar.gz" --strip-components=1 --directory=/usr/share/elasticsearch

# Replace the JDK
RUN rm -rf /usr/share/elasticsearch/jdk ; \
    mkdir -p /usr/share/elasticsearch/jdk_graal ; \
    mv /usr/java/* /usr/share/elasticsearch/jdk_graal
ENV	JAVA_HOME=/usr/share/elasticsearch/jdk_graal
ENV PATH /usr/share/elasticsearch/bin:$JAVA_HOME/bin:$PATH
RUN elasticsearch-plugin install --batch file:///home/gradle/plugins/analysis-phonetic/build/distributions/analysis-phonetic-${ELASTIC_VERSION}.zip
RUN elasticsearch-plugin install --batch file:///home/gradle/plugins/mapper-size/build/distributions/mapper-size-${ELASTIC_VERSION}.zip

FROM container-registry.oracle.com/os/oraclelinux:7-slim
ARG ELASTIC_VERSION=7.6.1

RUN groupadd -g 1000 elasticsearch && \
    adduser -u 1000 -g 1000 -G 0 -d /usr/share/elasticsearch elasticsearch && \
    chmod 0775 /usr/share/elasticsearch && \
    chgrp 0 /usr/share/elasticsearch

WORKDIR /usr/share/elasticsearch

ENV ELASTIC_CONTAINER true
ENV JAVA_HOME /usr/share/elasticsearch/jdk_graal
ENV PATH /usr/share/elasticsearch/bin:$JAVA_HOME/bin:$PATH
ENV ES_BUNDLED_JDK false
ENV ES_JAVA_OPTS "-Des.bundled_jdk=false"

COPY --from=0 --chown=1000:0 /usr/share/elasticsearch /usr/share/elasticsearch
COPY --chown=1000:0 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Openshift overrides USER and uses ones with randomly uid>1024 and gid=0
# Allow ENTRYPOINT (and ES) to run even with a different user
RUN chgrp 0 /usr/local/bin/docker-entrypoint.sh && \
    chmod g=u /etc/passwd && \
    chmod 0775 /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p config data logs && \
    chown -R 1000 config data logs && \
    chmod 0775 config data logs

# Use log4j config that logs only to stdout/stderr, not to any files
COPY --chown=1000:0 elasticsearch.yml log4j2.properties config/

EXPOSE 9200 9300

LABEL org.label-schema.schema-version="1.0" \
  org.label-schema.vendor="Elastic" \
  org.label-schema.name="elasticsearch" \
  org.label-schema.version="${ELASTIC_VERSION}" \
  org.label-schema.url="https://www.elastic.co/products/elasticsearch" \
  org.label-schema.vcs-url="https://github.com/verrazzano/elasticsearch"

# Add License and Readme files to the image
COPY LICENSE.txt README.asciidoc THIRD_PARTY_LICENSES.txt  /license/

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# Dummy overridable parameter parsed by entrypoint
CMD ["eswrapper"]
