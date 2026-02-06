# ---------- Stage 1: builder ----------
FROM php:8.2-cli AS builder

# OS deps (zip, git, icu, etc.)
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libicu-dev libpq-dev libonig-dev libpng-dev \
 && docker-php-ext-install intl pdo pdo_mysql zip \
 && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Xdebug optionnel pour la CI (couverture) — activable via env
# (n'active réellement xdebug que si besoin via variable)
ARG ENABLE_XDEBUG=0
RUN if [ "$ENABLE_XDEBUG" = "1" ]; then pecl install xdebug && docker-php-ext-enable xdebug; fi

# Optimisations Composer
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

WORKDIR /app

# 1) Étape cache-friendly : ne copier que les manifests
COPY composer.json composer.lock ./

# 2) Installer les deps SANS scripts (artisan pas encore là)
RUN mkdir -p ${COMPOSER_CACHE_DIR} \
 && composer install --no-interaction --prefer-dist --no-ansi --no-progress --no-scripts --no-dev

# 3) Copier le code complet (artisan arrive maintenant)
COPY . .

# 4) Rejouer les scripts après présence d’artisan
#    (dump autoload optimisé + découvertes + caches si besoin)
RUN composer dump-autoload -o \
 && php artisan package:discover --ansi \
 && php artisan config:cache \
 && php artisan route:cache || true
# Le "|| true" sur les caches évite d'échouer si certaines dépendances
# ne sont pas prêtes en CI; à ajuster selon ton cas.

# ---------- Stage 2: runtime ----------
FROM php:8.2-fpm AS runtime

RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev libpq-dev libpng-dev \
 && docker-php-ext-install intl pdo pdo_mysql zip \
 && rm -rf /var/lib/apt/lists/*

# Sécurité/permissions — exécuter sous www-data
WORKDIR /var/www/html

# Copier l’appli depuis builder
COPY --from=builder /app /var/www/html

# Ajuster les permissions minimales nécessaires (selon ton app)
# RUN chown -R www-data:www-data storage bootstrap/cache

# Variables à ajuster
ENV APP_ENV=production \
    APP_DEBUG=false

# Santé/Entrée
HEALTHCHECK --interval=30s --timeout=3s CMD php -v || exit 1
CMD ["php-fpm", "-F"]
