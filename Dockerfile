FROM php:7.1-apache

RUN systemMods=" \
        net-tools \
        vim \
        dialog \
        apt-utils \
        man-db \
        manpages-fr \
        curl \
        wget \
        openssl \
        acl \
        htop \
        git \
        graphicsmagick \
        apache2-utils \
        gnupg \
        unzip \
        libaio1 \
        libaio-dev \
        zlib1g-dev" && \
    apt-get update && \
    apt-get install -y $systemMods && \
    apt-get install -y libicu-dev && \
    apt-get clean && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN pecl install xdebug && \
    docker-php-ext-enable xdebug && \

    # opcache setup
    docker-php-ext-configure opcache --enable-opcache && \
    docker-php-ext-install opcache && \

    # intl extension
    docker-php-ext-configure intl && \
    docker-php-ext-install intl && \

    # APCu
    pecl install apcu && \
    docker-php-ext-enable apcu && \

    # PDO
    docker-php-ext-install pdo && \

    # ZIP
    docker-php-ext-install zip && \

    # PDO MYSQL
    docker-php-ext-install pdo_mysql

# COMPOSER
RUN wget https://composer.github.io/installer.sig -O - -q | tr -d '\n' > installer.sig && \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php -r "if (hash_file('SHA384', 'composer-setup.php') === file_get_contents('installer.sig')) { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    php -r "unlink('composer-setup.php'); unlink('installer.sig');"

# APACHE
RUN a2enmod rewrite \
    && a2enmod headers \
    && a2enmod deflate \
    && a2enmod ssl \
    && a2enmod proxy

# nodejs
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - && \
    apt-get install -y nodejs

# Install yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
    apt-get update && apt-get install yarn

# PHP
RUN ln -snf /usr/share/zoneinfo/Europe/Paris /etc/localtime && echo Europe/Paris > /etc/timezone
COPY etc/app.conf /etc/apache2/sites-available/
COPY etc/app.ini /usr/local/etc/php/conf.d/
COPY docker-php-entrypoint /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-php-entrypoint && \
    mkdir -p /var/log/app && \
    chown -R www-data:www-data /var/log/app && \
    a2dissite 000-default.conf && \
    a2ensite app.conf

WORKDIR /mnt/apps/app