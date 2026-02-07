# ---------- Stage 1: builder ----------
FROM php:8.2-cli AS builder

RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libicu-dev libpq-dev libonig-dev libpng-dev \
 && docker-php-ext-install intl pdo pdo_mysql zip \
 && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# PCOV pour la couverture (rapide en CI)
RUN pecl install pcov \
 && docker-php-ext-enable pcov

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

WORKDIR /app

# 1) Manifests seuls pour le cache
COPY composer.json composer.lock ./

# 2) Installer SANS scripts (artisan pas encore là)
RUN mkdir -p ${COMPOSER_CACHE_DIR} \
 && composer install --no-interaction --prefer-dist --no-ansi --no-progress --no-scripts --no-dev

# 3) Copier le code
COPY . .

# 4) Scripts Laravel une fois 'artisan' présent
RUN composer dump-autoload -o \
 && php artisan package:discover --ansi \
 && php artisan config:cache || true \
 && php artisan route:cache || true

# ---------- Stage 2: runtime ----------
FROM php:8.2-fpm AS runtime

RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev libpq-dev libpng-dev \
 && docker-php-ext-install intl pdo pdo_mysql zip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY --from=builder /app /var/www/html

ENV APP_ENV=production \
    APP_DEBUG=false

CMD ["php-fpm", "-F"]
