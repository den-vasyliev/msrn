FROM ubuntu:16.04
MAINTAINER den@msrn.me

# Install app
WORKDIR /opt/msrn
COPY msrn.bin /opt/msrn
# Configure
RUN ["chmod", "+x", "msrn.bin"]

EXPOSE 35001

# Run app
CMD ["/opt/msrn/msrn.bin"]