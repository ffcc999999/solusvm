hostname=$1
apt update -y
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
apt update -y
apt -y install php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server wget sudo
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
mysqlpass=`openssl rand -base64 16`
echo "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$mysqlpass'; CREATE DATABASE panel; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;" | mysql -u root
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
sed -i 's/^DB_PASSWORD.*$/DB_PASSWORD=$mysqlpass/' .env
sed -i 's/^APP_URL.*$/APP_URL=http://$hostname/' .env
php artisan migrate --seed --force
chown -R www-data:www-data /var/www/pterodactyl/*
rm /etc/nginx/sites-enabled/default
wget https://raw.githubusercontent.com/ffcc999999/solusvm/main/nginx_default.conf -O /etc/nginx/sites-available/pterodactyl.conf
sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
sed -i 's/^server_name <domain>.*$/server_name $hostname;/' /etc/nginx/sites-available/pterodactyl.conf
(crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
printf "[Unit]\nDescription=Pterodactyl Queue Worker\nAfter=redis-server.service\n\n[Service]\n# On some systems the user and group might be different.\n# Some systems use `apache` or `nginx` as the user and group.\nUser=www-data\nGroup=www-data\nRestart=always\nExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3\nStartLimitInterval=180\nStartLimitBurst=30\nRestartSec=5s\n\n[Install]\nWantedBy=multi-user.target\n" | sudo tee /etc/systemd/system/pteroq.service > /dev/null
systemctl enable redis-server
systemctl enable pteroq.service
