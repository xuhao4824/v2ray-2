#!/bin/bash

cd ~

domain=$1
if [[ ! $domain ]]
then
  echo "执行脚本时，请添加域名参数！"
  exit
fi

# 第一步：更新系统
sudo apt update

# 第二步：判断是否安装docker
isExistDocker=$(which docker)
if [[ ! $isExistDocker ]]
then
    sudo apt install -y docker.io
else
    # 判断是否有正在运行的v2ray容器,如果有，就强制删除
    v2rayContainer=$(docker ps -a -q -f name=v2ray)
    if [[ $v2rayContainer ]]; then
	    docker rm -f $v2rayContainer
    fi

    # 判断是否有v2ray镜像，如果有，就强制删除
    v2rayImagename=$(docker images | grep v2ray | tr -s ' ' | cut -d ' ' -f1)
    if [[ $v2rayImagename ]]
    then
	    docker rmi -f $v2rayImagename
    fi
fi

# 第三步：创建工作目录
if [[ -d v2ray ]]
then
    rm -rf v2ray
fi
mkdir v2ray
cd v2ray

# 第四步：创建v2ray 配置脚本config.json文件
cat  <<EOF >config.json
{
  "inbounds": [{
    "port": 18964,
    "protocol": "vmess",
    "streamSettings": {
      		"network":"ws",
        	"wsSettings": {
            "path": "/redemption"
          }
      },

    "settings": {
      "clients": [
        {
          "id": "f3ee4426-90c6-4343-a36b-bf5263de3892",
          "level": 1,
          "alterId": 64,
	        "security": "auto"
        }
      ]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
 
EOF

# 第五步：创建nginx 配置文件
cat > default <<EOF
server {
  listen 443 ssl;
  server_name $domain;

  ssl_certificate /root/https/server.crt;
  ssl_certificate_key /root/https/server.key;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers HIGH:!aNULL:!MD5;

  location /runToFreedom {
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:18964;
  }
}
EOF

# 第六步：创建v2ray 执行脚本run.sh
cat >run.sh <<EOF
#!/bin/bash
# run v2ray
/root/v2ray/v2ray -config /root/config.json &

# create https certs
mkdir /root/https
cd /root/https
openssl genrsa -out server.key 2048
expect -c "
		set timeout 10
		spawn openssl req -new -key server.key -out server.csr
		expect \"*Country Name*\" 
		send \"\r\"
		expect \"*State or Province Name*\" 
		send \"\r\"
		expect \"*Locality Name*\" 
		send \"\r\"
		expect \"*Organization Name*\" 
		send \"\r\"
		expect \"*Organizational Unit Name*\"
		send \"\r\"
		expect \"*Common Name*\"
		send \"$domain\r\"
		expect \"*Email Address*\"
		send \"\r\"
		expect \"*A challenge password*\"
		send \"\r\"
		expect \"*An optional company name*\"
		send \"\r\"
		interact
	"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

nginx &

bash

EOF

# 第七步：创建v2ray dockerfile文件
cat  <<EOF >dockerfile
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND noninteractive
COPY config.json /root/
COPY default /root/
COPY run.sh /root/
RUN apt-get update --fix-missing \
    && apt-get install -y wget \
    && apt-get install -y unzip \
    && apt-get install -y openssl \
    && apt-get install -y expect \
    && apt-get install -y vim \
    && chmod +x /root/run.sh
RUN mkdir /root/v2ray \
    && cd /root/v2ray \
    && wget https://github.com/v2fly/v2ray-core/releases/download/v4.27.0/v2ray-linux-64.zip \
    && unzip v2ray-linux-64.zip
RUN apt-get install -y nginx \
    && cp /root/default /etc/nginx/sites-available \
    && echo "daemon off;" >> /etc/nginx/nginx.conf
EXPOSE 443
ENTRYPOINT ["/root/run.sh"]

EOF

# 第八步：创建v2ray镜像
docker build -t v2ray .

# 第九步：创建启动v2ray容器
docker run -d -it --name v2ray -p 443:443 -p 80:80 v2ray

# 第十步：打开443端口
ufw allow 443


