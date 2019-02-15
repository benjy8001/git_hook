FROM php:7.2-fpm-alpine

RUN rm /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

COPY ./webapp /srv

VOLUME /srv
