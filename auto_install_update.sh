#!/bin/bash

apt-get install -y curl sudo docker docker-compose unzip nginx-full

#Сначала проверяем сертификат для ноды
# Путь к файлу cert.pem
CERT_PATH="/var/lib/marzban-node/cert.pem"

# Проверяем, существует ли файл cert.pem и не пуст ли он
if [[ -f "$CERT_PATH" && -s "$CERT_PATH" ]]; then
    echo "Файл cert.pem уже существует и не пуст. Продолжаем выполнение."
else
    if [[ ! -f "$CERT_PATH" ]]; then
        echo "Файл cert.pem не существует, создаю его."
        touch "$CERT_PATH"
    else
        echo "Файл cert.pem существует, но пуст. Пожалуйста, заполните его."
    fi

    # Запрашиваем у пользователя ввод сертификата
    echo "Введите сертификат в cert.pem (нажмите 'Enter' а потом еще раз 'Enter' для завершения):"

    # Инициализация временной переменной для хранения содержимого
    content=""

    while true; do
        read line
        if [[ -z "$line" ]]; then
            break
        fi
        content+="$line"$'\n' # добавляем введённую строку
    done

    # Записываем содержимое в файл cert.pem
    echo -e "$content" > "$CERT_PATH"
    echo "Содержимое записано в cert.pem."
fi

# Продолжение выполнения оставшейся части скрипта
LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name) \
&& echo "Последняя версия ${LATEST_VERSION}. Скачиваю ее." \
&& wget "https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/Xray-linux-64.zip" \
&& echo "Скачал, создаю папку /var/lib/marzban/xray-core." \
&& mkdir -p /var/lib/marzban/xray-core \
&& echo "Распаковка в папку." \
&& unzip -o Xray-linux-64.zip -d /var/lib/marzban/xray-core \
&& echo "Удаляю архив." \
&& rm Xray-linux-64.zip

# Удаляем контейнер, если он до этого существовал 
if [ "$(docker ps -aq -f name=marzban-node)" ]; then
    echo "Останавливаю докер"
    docker stop marzban-node
    echo "Удаляю докер"
    docker rm marzban-node
fi

echo "Делаю docker run с нуля"

docker run -d \
  --name marzban-node \
  --restart always \
  --network host \
  -e SSL_CLIENT_CERT_FILE="/var/lib/marzban-node/cert.pem" \
  -e XRAY_EXECUTABLE_PATH="/var/lib/marzban/xray-core/xray" \
  -e SERVICE_PORT="62050" \
  -e XRAY_API_PORT="62051" \
  -e SERVICE_PROTOCOL="rest" \
  -v /var/lib/marzban:/var/lib/marzban \
  -v /var/lib/marzban-node:/var/lib/marzban-node \
  gozargah/marzban-node:latest



#################

# выключаем двусторонний пинг 
if ! grep -Fxq "net.ipv4.icmp_echo_ignore_broadcasts=1" /etc/sysctl.conf; then
    echo "net.ipv4.icmp_echo_ignore_broadcasts=1" >> /etc/sysctl.conf
fi

if ! grep -Fxq "net.ipv4.icmp_echo_ignore_all=1" /etc/sysctl.conf; then
    echo "net.ipv4.icmp_echo_ignore_all=1" >> /etc/sysctl.conf
fi

# Применяем изменения
sysctl -p
#############


#nginx

# Путь к файлу конфигурации Nginx
NGINX_CONF="/etc/nginx/nginx.conf"

# Проверка, существует ли файл конфигурации
if [ -f "$NGINX_CONF" ]; then
    # Добавление блока в конец файла
    echo ""
    echo ""
    echo "stream {" >> "$NGINX_CONF"
    echo "    include /etc/nginx/stream-enabled/*.conf;" >> "$NGINX_CONF"
    echo "}" >> "$NGINX_CONF"
    echo "Блок добавлен в $NGINX_CONF."
else
    echo "Файл конфигурации $NGINX_CONF не найден."
fi

# Путь к директории и файлу
STREAM_ENABLED_DIR="/etc/nginx/stream-enabled"
PROXY_CONF_FILE="$STREAM_ENABLED_DIR/proxy.conf"

# Создание директории stream-enabled, если она не существует
if [ ! -d "$STREAM_ENABLED_DIR" ]; then
    mkdir "$STREAM_ENABLED_DIR"
    echo "Директория $STREAM_ENABLED_DIR создана."
else
    echo "Директория $STREAM_ENABLED_DIR уже существует."
fi

# Создание файла proxy.conf в директории stream-enabled
if [ ! -f "$PROXY_CONF_FILE" ]; then
    touch "$PROXY_CONF_FILE"
    echo "Файл $PROXY_CONF_FILE создан."
else
    echo "Файл $PROXY_CONF_FILE уже существует."
fi


# Путь к файлу конфигурации
CONF_FILE="/etc/nginx/stream-enabled/proxy.conf"

# Строки, которые нужно добавить
cat <<EOL >> $CONF_FILE
map \$ssl_preread_server_name \$sni_name {
    # hostnames;
    savesafe.cc      xray;
}

upstream xray {
    server 127.0.0.1:7891;
}

server {
    listen          443;
    proxy_pass      \$sni_name;
    ssl_preread     on;
}
EOL

# Проверка синтаксиса конфигурации Nginx
nginx -t

# Если проверка прошла успешно, перезагрузка Nginx
if [ $? -eq 0 ]; then
    systemctl reload nginx
else
    echo "Ошибка в конфигурации Nginx. Изменения не применены."
fi
