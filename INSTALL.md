# INSTALL

sudo bash

yum -y install git nginx

git -C /opt clone https://github.com/den-vasyliev/msrn.git

cd /opt/msrn;unzip "*.Z"

cp conf/* /etc/nginx

cp -r media /usr/share/nginx/html

service nginx start

chmod +x msrn.bin

aws configure

aws s3 cp s3://msrn/db/msrn.db .

env "REDIS_SERVER=msrn-cache.yrpj34.ng.0001.euc1.cache.amazonaws.com:6379"  ./msrn.bin

curl -d 'request_type=api_cmd;code=version;token=fa9fec615bf0b68aa631c68b0f85628d' 127.0.0.1

