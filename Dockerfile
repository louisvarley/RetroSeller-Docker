# Changes needed on the Dockerfile from PHP 7.3 to 7.4 :
# - gd configure options changed (from "--with-jpeg-dir=/usr/include/" to "--with-jpeg")
# - it is now required to install oniguruma lib for mbstring

# Pull base image.
FROM php:8.0.15-apache

# Install tools
RUN apt-get clean && apt-get update && apt-get install --fix-missing wget apt-transport-https lsb-release ca-certificates gnupg2 -y
RUN apt-get clean && apt-get update && apt-get install --fix-missing -y \
  ruby-dev \
  rubygems \
  imagemagick \
  graphviz \
  memcached \
  libmemcached-tools \
  libmemcached-dev \
  libjpeg62-turbo-dev \
  libmcrypt-dev \
  libxml2-dev \
  libxslt1-dev \
  default-mysql-client \
  sudo \
  git \
  vim \
  zip \
  wget \
  libaio1 \
  htop \
  iputils-ping \
  dnsutils \
  linux-libc-dev \
  libyaml-dev \
  libpng-dev \
  zlib1g-dev \
  libzip-dev \
  libicu-dev \
  libpq-dev \
  bash-completion \
  libldap2-dev \
  libssl-dev \
  libonig-dev


RUN DEBIAN_FRONTEND=noninteractive apt-get -y install mariadb-server

RUN mysql_dirs="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"
RUN for dir in $mysql_dirs; do mkdir -p $dir; chmod g+rwx $dir; chgrp -R 0 $dir; done

# Create new web user for apache and grant sudo without password
RUN useradd web -d /var/www -g www-data -s /bin/bash
RUN usermod -aG sudo web
RUN echo 'web ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Install sass and gem dependency
RUN apt-get install --fix-missing automake ruby-dev libtool -y

# Installation of Composer
#RUN cd /usr/src && curl -sS http://getcomposer.org/installer | php
#RUN cd /usr/src && mv composer.phar /usr/bin/composer

RUN curl -sS https://getcomposer.org/installer | php \
        && mv composer.phar /usr/local/bin/ \
        && ln -s /usr/local/bin/composer.phar /usr/local/bin/composer
ENV PATH="~/.composer/vendor/bin:./vendor/bin:${PATH}"


# Install xdebug. ver 3.1
RUN cd /tmp/ && wget http://xdebug.org/files/xdebug-3.1.0.tgz && tar -xvzf xdebug-3.1.0.tgz && cd xdebug-3.1.0/ && phpize && ./configure --enable-xdebug --with-php-config=/usr/local/bin/php-config && make && make install
RUN cd /tmp/xdebug-3.1.0 && cp modules/xdebug.so /usr/local/lib/php/extensions/
RUN echo 'zend_extension = /usr/local/lib/php/extensions/xdebug.so' >> /usr/local/etc/php/php.ini
RUN touch /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.remote_enable=1' >> /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.remote_autostart=0' >> /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.remote_connect_back=0' >> /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.remote_port=9000' >> /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.remote_log=/tmp/php7-xdebug.log' >> /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.remote_host=docker_host' >> /usr/local/etc/php/conf.d/xdebug.ini &&\
  echo 'xdebug.idekey=PHPSTORM' >> /usr/local/etc/php/conf.d/xdebug.ini

# Apache2 config
COPY config/apache2.conf /etc/apache2
COPY core/envvars /etc/apache2
COPY core/other-vhosts-access-log.conf /etc/apache2/conf-enabled/
RUN rm /etc/apache2/sites-enabled/000-default.conf

#added for AH00111 Error 
ENV APACHE_RUN_USER  www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR   /var/log/apache2
ENV APACHE_PID_FILE  /var/run/apache2/apache2.pid
ENV APACHE_RUN_DIR   /var/run/apache2
ENV APACHE_LOCK_DIR  /var/lock/apache2
ENV APACHE_LOG_DIR   /var/log/apache2

# Install php extensions + added mysqli install
RUN docker-php-ext-install opcache pdo_mysql && docker-php-ext-install mysqli
RUN docker-php-ext-configure gd --with-jpeg
RUN docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/
RUN docker-php-ext-install gd mbstring zip soap pdo_mysql mysqli xsl opcache calendar intl exif pgsql pdo_pgsql ftp bcmath ldap

# Custom Opcache
RUN ( \
  echo "opcache.memory_consumption=128"; \
  echo "opcache.interned_strings_buffer=8"; \
  echo "opcache.max_accelerated_files=20000"; \
  echo "opcache.revalidate_freq=5"; \
  echo "opcache.fast_shutdown=1"; \
  echo "opcache.enable_cli=1"; \
  ) >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini

# Apache encore de la config
RUN rm -rf /var/www/html && \
  mkdir -p /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html && \
  chown -R web:www-data /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html
RUN a2enmod rewrite expires ssl && service apache2 restart

# install msmtp
RUN set -x \
    && DEBIAN_FRONTEND=noninteractive \
    && apt-get update && apt-get install -y --no-install-recommends msmtp && rm -r /var/lib/apt/lists/*
ADD core/msmtprc.conf /usr/local/etc/msmtprc
ADD core/php-smtp.ini /usr/local/etc/php/conf.d/php-smtp.ini


# create directory for ssh keys
RUN mkdir /var/www/.ssh/
RUN chown -R web:www-data /var/www/

# Expose 80,443 
EXPOSE 80 443

# Add web .bashrc config
COPY config/bashrc /var/www/
RUN mv /var/www/bashrc /var/www/.bashrc
RUN chown www-data:www-data /var/www/.bashrc
RUN echo "source .bashrc" >> /var/www/.profile ;\
    chown www-data:www-data /var/www/.profile

# Add web and root .bashrc config
# When you "docker exec -it" into the container, you will be switched as web user and placed in /var/www/html
RUN echo "exec su - web" > /root/.bashrc && \
    echo ". .profile" > /var/www/.bashrc && \
    echo "alias ll='ls -al'" > /var/www/.profile && \
    echo "cd /var/www/html" >> /var/www/.profile

# Download RetroSeller, Update and General Models
RUN git clone https://github.com/louisvarley/RetroSeller /var/www/html

WORKDIR /var/www/html
RUN cd /var/www/html

RUN composer update    
RUN composer dump-autoload -o

# Create Config
ENV RETROSELLER_DEBUG_MODE false
ENV RETROSELLER_SQL_DUMP mysqldump
ENV RETROSELLER_SQL_HOST mysql
ENV RETROSELLER_SQL_NAME retroseller
ENV RETROSELLER_SQL_USER retroseller
ENV RETROSELLER_SQL_PASSWORD retroseller
ENV RETROSELLER_SQL_PORT 3306
ENV RETROSELLER_USERNAME admin@admin.com
ENV RETROSELLER_PASSWORD admin

RUN echo "<?php\n" \
         "\n" \
         "/* Debug Mode */\n" \
         "define('_SHOW_ERRORS', ${RETROSELLER_DEBUG_MODE});\n" \
         "\n" \
         "/* Database Config */\n" \
         "define('_DB_HOST','${RETROSELLER_SQL_HOST}');\n" \
         "define('_DB_NAME','${RETROSELLER_SQL_NAME}');\n" \
         "define('_DB_USER','${RETROSELLER_SQL_USER}');\n" \
         "define('_DB_PASSWORD','${RETROSELLER_SQL_PASSWORD}');\n" \
         "define('_DB_PORT','${RETROSELLER_SQL_PORT}');\n" \
         "define('_DB_DUMPER','${RETROSELLER_SQL_DUMP}');\n" \
         "\n" \
         "/* Admin Login */\n" \
         "define('_ADMIN_USER','${RETROSELLER_USERNAME}');\n" \
         "define('_ADMIN_PASSWORD','${RETROSELLER_PASSWORD}');\n" > /var/www/html/app/Config.php


RUN mkdir /var/www/html/core/Proxies
RUN chown -R web:www-data /var/www/html/core/Proxies
RUN chmod -R 777 /var/www/html/core/Proxies

# Set and run a custom entrypoint
COPY core/docker-entrypoint.sh /
RUN chmod 777 /docker-entrypoint.sh && chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# CMD ["cat", "/etc/apache2/envvars"]
# CMD ["sed", "-n", "39p", "/etc/apache2/apache2.conf"]


