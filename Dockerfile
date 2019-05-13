FROM centos:7 as build

RUN yum -y update && yum clean all

# cmake3
RUN yum -y install --setopt=skip_missing_names_on_install=False epel-release

RUN yum -y install --setopt=skip_missing_names_on_install=False \
    java-11-openjdk-devel \
    java-11-openjdk \
    protobuf protobuf-compiler \
    patch \
    lzo-devel zlib-devel gcc gcc-c++ make autoconf automake libtool openssl-devel fuse-devel \
    cmake3 \
    && yum clean all \
    && rm -rf /var/cache/yum


#Install maven
# set installed Maven version you can easily change it later
ENV MAVEN_VERSION 3.6.0

RUN set -x; curl -sSL http://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz \
    | tar xzf - -C /usr/share \
    && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
    && sed -i 's|${CLASSWORLDS_LAUNCHER} "$@"|${CLASSWORLDS_LAUNCHER} -B "$@"|g' /usr/share/maven/bin/mvn \
    && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

RUN echo "export M2_HOME=/usr/share/maven" >> /etc/profile

RUN ln -s /usr/bin/cmake3 /usr/bin/cmake

RUN mkdir /build
COPY .git /build/.git
COPY hadoop-yarn-project /build/hadoop-yarn-project
COPY hadoop-assemblies /build/hadoop-assemblies
COPY hadoop-project /build/hadoop-project
COPY hadoop-common-project /build/hadoop-common-project
COPY hadoop-cloud-storage-project /build/hadoop-cloud-storage-project
COPY hadoop-project-dist /build/hadoop-project-dist
COPY hadoop-maven-plugins /build/hadoop-maven-plugins
COPY hadoop-dist /build/hadoop-dist
COPY hadoop-minicluster /build/hadoop-minicluster
COPY hadoop-mapreduce-project /build/hadoop-mapreduce-project
COPY hadoop-tools /build/hadoop-tools
COPY hadoop-hdfs-project /build/hadoop-hdfs-project
COPY hadoop-client-modules /build/hadoop-client-modules
COPY hadoop-build-tools /build/hadoop-build-tools
COPY dev-support /build/dev-support
COPY pom.xml /build/pom.xml
COPY LICENSE.txt /build/LICENSE.txt
COPY BUILDING.txt /build/BUILDING.txt
COPY NOTICE.txt /build/NOTICE.txt
COPY README.txt /build/README.txt

ENV CMAKE_C_COMPILER=gcc CMAKE_CXX_COMPILER=g++

WORKDIR /build
RUN mvn -B -e -Dtest=false -DskipTests -Dmaven.javadoc.skip=true clean package -Pdist,native -Dtar

FROM centos:7

RUN yum install --setopt=skip_missing_names_on_install=False -y \
        epel-release \
    && yum install --setopt=skip_missing_names_on_install=False -y \
        java-11-openjdk \
        java-11-openjdk-devel \
        curl \
        less  \
        procps \
        net-tools \
        bind-utils \
        which \
        jq \
    && yum clean all \
    && rm -rf /tmp/* /var/tmp/*

ENV JAVA_HOME=/etc/alternatives/jre

ENV HADOOP_VERSION 3.1.1

ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CLASSPATH=$HADOOP_HOME/share/hadoop/tools/lib/*
ENV HADOOP_CONF_DIR=/etc/hadoop
ENV PATH=$HADOOP_HOME/bin:$PATH

COPY --from=build /build/hadoop-dist/target/hadoop-$HADOOP_VERSION /opt/hadoop
# remove unnecessary doc/src files
RUN rm -rf ${HADOOP_HOME}/share/doc \
    && for dir in common hdfs mapreduce tools yarn; do \
         rm -rf ${HADOOP_HOME}/share/hadoop/${dir}/sources; \
       done \
    && rm -rf ${HADOOP_HOME}/share/hadoop/common/jdiff \
    && rm -rf ${HADOOP_HOME}/share/hadoop/mapreduce/lib-examples \
    && rm -rf ${HADOOP_HOME}/share/hadoop/yarn/test \
    && find ${HADOOP_HOME}/share/hadoop -name *test*.jar | xargs rm -rf

RUN mkdir -p /opt/hadoop/logs

# https://docs.oracle.com/javase/7/docs/technotes/guides/net/properties.html
# Java caches dns results forever, don't cache dns results forever:
RUN sed -i '/networkaddress.cache.ttl/d' $JAVA_HOME/lib/security/java.security
RUN sed -i '/networkaddress.cache.negative.ttl/d' $JAVA_HOME/lib/security/java.security
RUN echo 'networkaddress.cache.ttl=0' >> $JAVA_HOME/lib/security/java.security
RUN echo 'networkaddress.cache.negative.ttl=0' >> $JAVA_HOME/lib/security/java.security

RUN useradd hadoop -m -u 1002 -d $HADOOP_HOME

# imagebuilder expects the directory to be created before VOLUME
RUN mkdir -p /hadoop/dfs/data /hadoop/dfs/name
# to allow running as non-root
RUN chown -R 1002:0 /opt /hadoop /hadoop /etc/hadoop && \
    chmod -R 774 /opt /hadoop /etc/hadoop /etc/passwd

VOLUME /hadoop/dfs/data /hadoop/dfs/name

USER 1002

LABEL io.k8s.display-name="OpenShift Hadoop" \
      io.k8s.description="This is an image used by operator-metering to to install and run HDFS." \
      io.openshift.tags="openshift" \
      maintainer="Chance Zibolski <czibolsk@redhat.com>"

