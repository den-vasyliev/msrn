FROM ubuntu:16.04
MAINTAINER den@msrn.me
RUN apt-get -y update
RUN apt-get install -y libcurl3
# Install app
WORKDIR /opt/msrn
RUN wget https://$(curl -s https://circleci.com/api/v1.1/project/github/den-vasyliev/msrn|grep build_url|cut -d '/' -f 7|tr -d '\",'|head -1)-98475363-gh.circle-artifacts.com/0/build/msrn.bin
COPY msrn.bin msrn.bin
# Configure
RUN ["chmod", "+x", "msrn.bin"]

EXPOSE 35001

# Run app
CMD ["/opt/msrn/msrn.bin"]