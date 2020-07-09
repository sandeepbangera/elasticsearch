Build Instructions
===
## Pre-requisites
1. Download Oracle GraalVM Enterprise Edition 20.1.0.1 Linux x86 for Java 11 (Oracle GraalVM Enterprise Edition Core)
   * from: https://www.oracle.com/downloads/graalvm-downloads.html
   * with SHA256: 870e51d13e7f42df50097110b14715e765e2a726aa2609c099872995c4409d8f
   * to: project's root directory.

## Build

`docker image build --build-arg GRAALVM_BINARY=graalvm-ee-java11-linux-amd64-20.1.0.1.tar.gz -t <docker-image-repo>/elasticsearch:7.6.1-2 .`

## Push to OCIR

`docker image push <docker-image-repo>/elasticsearch:7.6.1-2`
