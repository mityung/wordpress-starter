ARG PHP_VERSION=7.3
FROM php:${PHP_VERSION}-apache
ARG VERSION=latest
LABEL maintainer="Derek P Sifford <dereksifford@gmail.com>" \
      version="${VERSION}-php${PHP_VERSION}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY sendmailconfig.sh /usr/local/sbin/sendmailconfig.sh

# Install base requirements & sensible defaults + required PHP extensions
# hadolint ignore=DL3008
RUN echo "deb http://ftp.debian.org/debian $(sed -n 's/^VERSION=.*(\(.*\)).*/\1/p' /etc/os-release)-backports main" >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        bindfs \
        ghostscript \
        less \
        libjpeg-dev \
        libmagickwand-dev \
        libpng-dev \
        libxml2-dev \
        libzip-dev \
        mariadb-client \
        sudo \
        unzip \
        vim \
        zip \
        expect \
        sendmail \
    && /usr/local/sbin/sendmailconfig.sh \
    && apt-get -t "$(sed -n 's/^VERSION=.*(\(.*\)).*/\1/p' /etc/os-release)-backports" install -y --no-install-recommends \
        python-certbot-apache \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
    && docker-php-ext-configure zip --with-libzip \
    && pecl install imagick \
    && pecl install redis \
    && pecl install xdebug \
    && docker-php-ext-install \
        bcmath \
        exif \
        gd \
        mysqli \
        opcache \
        soap \
        zip \
        pdo \
        pdo_mysql \
    && docker-php-ext-enable imagick \
    && docker-php-ext-enable redis \
    && docker-php-ext-enable xdebug \
    # See https://secure.php.net/manual/en/opcache.installation.php
    && echo 'memory_limit = 512M' >> /usr/local/etc/php/php.ini \
    && { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=2'; \
        echo 'opcache.fast_shutdown=1'; \
        echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini \
    && sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf \
    # Fixes issue where error is logged stating apache could not resolve the
    # fully qualified domain name
    && echo 'ServerName localhost' > /etc/apache2/conf-available/fqdn.conf \
    # Grab and install wp-cli from remote
    && curl --create-dirs \
        -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /etc/bash_completion.d/wp-cli https://raw.githubusercontent.com/wp-cli/wp-cli/master/utils/wp-completion.bash \
    && a2enconf fqdn \
    && a2enmod rewrite expires

# Add admin superuser, create install directory, adjust perms, & add symlink
COPY run.sh /run.sh
RUN useradd -ms /bin/bash -G sudo admin \
    && echo "admin ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/admin \
    && chmod 0440 /etc/sudoers.d/admin \
    && chmod +x /usr/local/bin/wp /run.sh \
    && mkdir -m 0700 /app \
    && chown admin:admin /app \
    && printf '%s\t%s\t%s\t%s%s%s%s%s%s%s%s\t%d\t%d\n' \
        '/app' \
        '/var/www/html' \
        'fuse.bindfs' \
            'force-user=www-data,' \
            'force-group=www-data,' \
            'create-for-user=admin,' \
            'create-for-group=admin,' \
            'create-with-perms=0644:a+X,' \
            'chgrp-ignore,' \
            'chown-ignore,' \
            'chmod-ignore' \
        0 \
        0 > /etc/fstab

USER admin
# explanation for not having /var/www/html as workdir
# https://github.com/visiblevc/wordpress-starter/pull/136
WORKDIR /app
EXPOSE 80 443
CMD ["/run.sh"]
