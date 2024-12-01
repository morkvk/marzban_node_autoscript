#!/bin/bash

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

# Удаляем контейнер, если он существует
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
