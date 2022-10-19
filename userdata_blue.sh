#!/bin/bash
S3_BUCKET=red-blue-html-s3
COLOR=blue
# Install Nginx
amazon-linux-extras install -y nginx1.12

# Start Nginx
systemctl enable nginx
systemctl start nginx

# Create a directory for the index.html file
mkdir -p /www/
chmod 0755 /www/

# Download index.html file to the instance
aws s3 cp s3://${S3_BUCKET}/$COLOR/index.html /www/$COLOR/

# Replace Nginx configuration with one which serves a static index.html file
echo "user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '
                      '\$status \$body_bytes_sent \"\$http_referer\" '
                      '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;
        root         /www/$COLOR;
        index        index.html;

        location ~ /$COLOR/? {
            root         /www;
        }
    }
}" >/etc/nginx/nginx.conf

# Restart Nginx
systemctl restart nginx