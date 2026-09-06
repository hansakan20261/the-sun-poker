FROM nginx:alpine

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy download page
COPY index.html /usr/share/nginx/html/index.html

# Copy APK files
COPY apk/ /usr/share/nginx/html/apk/

EXPOSE 80
