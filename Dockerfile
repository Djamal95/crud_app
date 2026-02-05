# ---------- Stage 1: builder ----------
FROM php:8.2-cli AS builder

# OS deps (ex: zip, git, libicu, libonig si nécessaire)
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libicu-dev libpq-dev libonig-dev libpng-dev \
 && docker-php-ext-install intl pdo pdo_mysql zip \
 && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Xdebug optionnel pour la CI (couverture) — activable via env
RUN pecl install xdebug && docker-php-ext-enable xdebug || true

WORKDIR /app
# Copie des manifestes pour tirer profit du cache
COPY composer.json composer.lock ./

# Install deps en mode dev (CI), cache Composer dans /tmp/composer-cache
ARG COMPOSER_CACHE_DIR=/tmp/composer-cache
RUN mkdir -p ${COMPOSER_CACHE_DIR}
RUN composer install --no-interaction --prefer-dist --no-ansi --no-progress

# Copie du code (après install pour profiter du cache)
COPY . .

# ---------- Stage 2: runtime ----------
FROM php:8.2-fpm AS runtime

RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev libpq-dev libpng-dev \
 && docker-php-ext-install intl pdo pdo_mysql zip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
# On ne copie que l’essentiel depuis builder
COPY --from=builder /app /var/www/html

# Variables à ajuster
ENV APP_ENV=production \
    APP_DEBUG=false

# Entrypoint / healthcheck éventuels
CMD ["php-fpm", "-F"]
