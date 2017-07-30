FROM msrn:latest
MAINTAINER den@msrn.me
# Install dependencies!!!
RUN apt-get update -y
RUN apt-get install -y nginx curl

# Install app
WORKDIR /opt/msrn
COPY conf/ /etc/nginx
ADD media /usr/share/nginx/html
COPY msrn.db /opt/msrn
COPY msrn.bin /opt/msrn

# Configure
ENV REDIS_SERVER msrn-cache.yrpj34.ng.0001.euc1.cache.amazonaws.com:6379
RUN ["/usr/sbin/nginx"]
RUN ["chmod", "+x", "msrn.bin"]

EXPOSE 80
EXPOSE 443

# Run app
RUN  ["/opt/msrn/msrn.bin"]
