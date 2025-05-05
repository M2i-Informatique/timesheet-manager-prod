FROM php:8.2-fpm-alpine

# Installation des dépendances système nécessaires
RUN apk add --no-cache \
    build-base \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    zip \
    jpegoptim \
    optipng \
    pngquant \
    gifsicle \
    vim \
    unzip \
    git \
    curl \
    postgresql-dev \
    libzip-dev \
    icu-dev \
    g++

# Installer les extensions PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j$(nproc) pdo pdo_pgsql pgsql gd zip intl calendar

# Installer Composer
COPY --from=composer:2.6.5 /usr/bin/composer /usr/bin/composer

# Installer Node.js et npm
RUN apk add --no-cache nodejs npm

# Définir le répertoire de travail
WORKDIR /var/www

# Copier les fichiers du projet
COPY ./www/ /var/www/

EXPOSE 9000

CMD ["php-fpm"]
