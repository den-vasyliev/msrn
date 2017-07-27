# INSTALL

# aws configure
 
FROM ubuntu:17.04

# Install dependencies
RUN apt-get update -y
RUN apt-get install -y git nginx

# Install app
WORKDIR /opt
RUN git -C /opt clone https://github.com/den-vasyliev/msrn.git
WORKDIR /opt/msrn
COPY conf/* /etc/nginx
ADD media /usr/share/nginx/html
RUN "aws s3 cp s3://msrn/db/msrn.db ."

# Configure
ENV REDIS_SERVER msrn-cache.yrpj34.ng.0001.euc1.cache.amazonaws.com:6379
RUN "service nginx start"
RUN ["chmod", "+x", "msrn.bin"]

EXPOSE 80
EXPOSE 443

# Run app
CMD  "./msrn.bin"

#Test
#curl -d 'request_type=api_cmd;code=version;token=fa9fec615bf0b68aa631c68b0f85628d' 127.0.0.1

