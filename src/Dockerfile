FROM ubuntu:16.04
MAINTAINER den@msrn.me
RUN apt-get -y update
RUN apt-get install -y libcurl3
# Install app
WORKDIR /opt/msrn
COPY msrn.bin msrn.bin
# Configure
RUN ["chmod", "+x", "msrn.bin"]

EXPOSE 35001

# Run app
CMD ["/opt/msrn/msrn.bin"]