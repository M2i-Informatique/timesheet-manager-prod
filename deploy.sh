#!/bin/bash

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Fonctions d'aide
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${YELLOW}=====================================================${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}=====================================================${NC}\n"
}

# Vérifier si l'utilisateur est root - rendre cette vérification optionnelle
if [ "$EUID" -ne 0 ]; then
  print_info "Avertissement: Certaines opérations peuvent nécessiter des droits root."
  read -p "Voulez-vous continuer sans sudo? (y/n): " CONTINUE_WITHOUT_SUDO
  if [ "$CONTINUE_WITHOUT_SUDO" != "y" ]; then
      print_error "Exécutez le script avec sudo."
      exit 1
  fi
fi

# Stocker l'utilisateur réel pour les opérations Git
REAL_USER=$(whoami)
if [ "$EUID" -eq 0 ] && [ ! -z "$SUDO_USER" ]; then
    REAL_USER=$SUDO_USER
fi

print_header "SCRIPT DE DÉPLOIEMENT AUTOMATISÉ LARAVEL + DOCKER + POSTGRESQL + CERTBOT"

# Demander les informations à l'utilisateur
read -p "Entrez votre nom de domaine (ex: example.com): " DOMAIN_NAME
read -p "Entrez votre adresse email: " EMAIL
read -p "Entrez l'URL du dépôt Git (ex: git@github.com:user/repo.git): " GIT_URL

# Demander les informations de base de données
read -p "Entrez le nom de la base de données (défaut: laravel_db): " DB_NAME
DB_NAME=${DB_NAME:-laravel_db}
read -p "Entrez le nom d'utilisateur de la base de données (défaut: root): " DB_USER
DB_USER=${DB_USER:-root}
read -p "Entrez le mot de passe de la base de données (défaut: secretpass): " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-secretpass}
read -p "Entrez le mot de passe pour pgAdmin (défaut: admin): " PGADMIN_PASSWORD
PGADMIN_PASSWORD=${PGADMIN_PASSWORD:-admin}

# Option pour utiliser HTTPS au lieu de SSH pour Git
if [[ "$GIT_URL" == git@* ]]; then
    read -p "Utiliser HTTPS pour le clonage Git (recommandé si vous avez des problèmes de clé SSH)? (y/n): " USE_HTTPS
    if [ "$USE_HTTPS" = "y" ]; then
        # Convertir URL SSH en HTTPS
        REPO_PATH=$(echo "$GIT_URL" | sed 's/git@\(.*\):\(.*\)/\2/')
        DOMAIN=$(echo "$GIT_URL" | sed 's/git@\(.*\):.*/\1/')
        GIT_URL="https://$DOMAIN/$REPO_PATH"
        print_info "URL convertie en HTTPS: $GIT_URL"
    fi
fi

# Option pour une branche spécifique
read -p "Souhaitez-vous cloner une branche spécifique? (y/n): " USE_BRANCH
if [ "$USE_BRANCH" = "y" ]; then
  read -p "Entrez le nom de la branche: " BRANCH_NAME
fi

# Vérification des informations
print_info "Vérification des informations:"
echo "Nom de domaine: $DOMAIN_NAME"
echo "Email: $EMAIL"
echo "URL du dépôt Git: $GIT_URL"
if [ "$USE_BRANCH" = "y" ]; then
  echo "Branche: $BRANCH_NAME"
fi
echo "Base de données: $DB_NAME"
echo "Utilisateur DB: $DB_USER"
echo "Mot de passe DB: $DB_PASSWORD"
echo "Mot de passe pgAdmin: $PGADMIN_PASSWORD"
read -p "Ces informations sont-elles correctes? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    print_error "Déploiement annulé."
    exit 1
fi

# Création des répertoires nécessaires
print_header "CRÉATION DES RÉPERTOIRES"
print_info "Création des répertoires nécessaires..."
mkdir -p certbot/conf certbot/www www server

# Création du fichier .gitignore
print_header "CRÉATION DU FICHIER .gitignore"
print_info "Création du fichier .gitignore..."
cat > .gitignore << EOF
.idea
.vscode
.DS_Store
.env
www

pgdata/

backup_postgres.sh
backups/
EOF
print_success "Fichier .gitignore créé."

# Création d'un fichier .env temporaire pour stocker les variables d'environnement
print_header "CRÉATION DU FICHIER .env"
print_info "Création du fichier .env..."
cat > .env << EOF
DOMAIN_NAME=$DOMAIN_NAME
EMAIL=$EMAIL
PGADMIN_DEFAULT_EMAIL=$EMAIL
PGADMIN_DEFAULT_PASSWORD=$PGADMIN_PASSWORD
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
EOF
print_success "Fichier .env créé."

# Création du fichier Dockerfile optimisé
print_header "CRÉATION DU DOCKERFILE"
print_info "Création du Dockerfile..."
cat > Dockerfile << EOF
FROM php:8.2-fpm-alpine

# Installation des dépendances système nécessaires
RUN apk add --no-cache \\
    build-base \\
    libpng-dev \\
    libjpeg-turbo-dev \\
    freetype-dev \\
    zip \\
    jpegoptim \\
    optipng \\
    pngquant \\
    gifsicle \\
    vim \\
    unzip \\
    git \\
    curl \\
    postgresql-dev \\
    libzip-dev \\
    icu-dev \\
    g++

# Installer les extensions PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \\
    && docker-php-ext-configure intl \\
    && docker-php-ext-install -j\$(nproc) pdo pdo_pgsql pgsql gd zip intl calendar

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
EOF
print_success "Dockerfile créé."

# Création du fichier compose.yml
print_header "CRÉATION DU FICHIER COMPOSE.YML"
print_info "Création du fichier compose.yml..."
cat > compose.yml << EOF
services:
  app:
    build: .
    image: timesheet-manager:1.0
    container_name: timesheet-manager
    restart: unless-stopped
    volumes:
      - ./www:/var/www
      - ./server/php-local.ini:/usr/local/etc/php/conf.d/local.ini
    networks:
      - app_network
    ports:
      - "9000:9000"
    depends_on:
      - db
      
  db:
    image: postgres:16.4-alpine
    container_name: postgres_db
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${DB_NAME}
      POSTGRES_USER: \${DB_USER}
      POSTGRES_PASSWORD: \${DB_PASSWORD}
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    networks:
      - app_network

  pgadmin:
    image: dpage/pgadmin4:8.4
    container_name: pgadmin
    restart: unless-stopped
    environment:
      PGADMIN_DEFAULT_EMAIL: \${PGADMIN_DEFAULT_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: \${PGADMIN_DEFAULT_PASSWORD}
    ports:
      - "5050:80"
    depends_on:
      - db
    networks:
      - app_network

  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./server/default.conf:/etc/nginx/conf.d/default.conf
      - ./www:/var/www
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    depends_on:
      - app
    networks:
      - app_network

  certbot:
    image: certbot/certbot:v2.8.0
    container_name: certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
      - ./www:/var/www
    depends_on:
      - nginx
    networks:
      - app_network

networks:
  app_network:

volumes:
  pgdata:
EOF
print_success "Fichier compose.yml créé."

# Création des fichiers de configuration Nginx
print_header "CRÉATION DES FICHIERS DE CONFIGURATION NGINX"
print_info "Création du fichier template Nginx..."
cat > server/default.conf.template << 'EOF'
# Définir un resolver DNS pour l'OCSP stapling
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;

server {
    listen 80;
    listen [::]:80;
    server_name @DOMAIN_NAME@ www.@DOMAIN_NAME@;
    
    # Pour les défis Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirection vers HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name @DOMAIN_NAME@ www.@DOMAIN_NAME@;

    ssl_certificate /etc/letsencrypt/live/@DOMAIN_NAME@/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/@DOMAIN_NAME@/privkey.pem;
    
    # Configuration SSL optimisée
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # En-têtes de sécurité
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "no-referrer-when-downgrade";

    root /var/www/public;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

    # Mise en cache des ressources statiques
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

# Création du fichier PHP ini
print_info "Création du fichier php-local.ini..."
cat > server/php-local.ini << EOF
memory_limit = 512M
upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
EOF
print_success "Fichiers de configuration Nginx et PHP créés."

# Remplacer les variables dans la configuration Nginx
print_info "Configuration du serveur Nginx avec votre domaine..."
sed "s|@DOMAIN_NAME@|$DOMAIN_NAME|g" server/default.conf.template > server/default.conf

# Cloner le dépôt Git avec l'utilisateur réel
print_header "CLONAGE DU DÉPÔT GIT"
print_info "Clonage du dépôt Git dans le dossier www..."

# Supprimer le dossier www s'il existe déjà
if [ -d "www" ]; then
    print_info "Suppression du dossier www existant..."
    rm -rf www
fi

# Cloner le dépôt en utilisant l'utilisateur réel
if [ "$EUID" -eq 0 ] && [ ! -z "$SUDO_USER" ]; then
    print_info "Clonage du dépôt Git avec l'utilisateur $REAL_USER..."
    if [ "$USE_BRANCH" = "y" ]; then
        su - $REAL_USER -c "cd $(pwd) && git clone --branch \"$BRANCH_NAME\" \"$GIT_URL\" www"
    else
        su - $REAL_USER -c "cd $(pwd) && git clone \"$GIT_URL\" www"
    fi
else
    if [ "$USE_BRANCH" = "y" ]; then
        git clone --branch "$BRANCH_NAME" "$GIT_URL" www
    else
        git clone "$GIT_URL" www
    fi
fi

if [ $? -ne 0 ]; then
    print_error "Échec du clonage du dépôt Git."
    print_info "Continuez l'installation en supposant que vous avez déjà cloné le dépôt? (y/n): "
    read CONTINUE_WITHOUT_GIT
    if [ "$CONTINUE_WITHOUT_GIT" != "y" ]; then
        exit 1
    fi
else
    print_success "Dépôt Git cloné avec succès dans le dossier www."
fi

# Vérifier si le dossier www existe
if [ ! -d "www" ]; then
    print_error "Le dossier www n'existe pas. Veuillez le créer manuellement et y placer votre application Laravel."
    exit 1
fi

# Configuration du fichier .env de Laravel
print_header "CONFIGURATION DU FICHIER .ENV LARAVEL"
print_info "Configuration du fichier .env Laravel..."

if [ -f "www/.env.example" ]; then
    cp www/.env.example www/.env
    
    # Modifier les variables d'environnement pour la base de données
    sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=pgsql/' www/.env
    sed -i 's/DB_HOST=.*/DB_HOST=db/' www/.env
    sed -i 's/DB_PORT=.*/DB_PORT=5432/' www/.env
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" www/.env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" www/.env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" www/.env
    
    # Ajouter l'APP_URL avec le domaine
    sed -i "s#APP_URL=.*#APP_URL=https://$DOMAIN_NAME#" www/.env
    
    print_success "Fichier .env Laravel configuré."
else
    print_error "Fichier .env.example non trouvé dans le dépôt. Création d'un nouveau fichier .env."
    # Création d'un fichier .env de base
    cat > www/.env << EOF
APP_NAME=Laravel
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://$DOMAIN_NAME

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=warning

DB_CONNECTION=pgsql
DB_HOST=db
DB_PORT=5432
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASSWORD

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=database
SESSION_LIFETIME=120

MEMCACHED_HOST=127.0.0.1

MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="\${APP_NAME}"
EOF
    print_success "Fichier .env Laravel créé."
fi

# Build de l'image Docker
print_header "BUILD DE L'IMAGE DOCKER"
print_info "Construction de l'image Docker..."
docker build -t timesheet-manager:1.0 .

if [ $? -ne 0 ]; then
    print_error "Échec de la construction de l'image Docker."
    exit 1
fi

print_success "Image Docker construite avec succès."

# Démarrer les conteneurs sans Certbot d'abord pour configurer le serveur web
print_header "DÉMARRAGE DES CONTENEURS"
print_info "Démarrage des conteneurs (sans HTTPS pour l'instant)..."
docker compose up -d nginx

# Attendre que Nginx soit prêt
print_info "Attente que Nginx soit prêt..."
sleep 5

# Exécution de Certbot en mode manuel pour Let's Encrypt
print_header "OBTENTION DU CERTIFICAT SSL"
print_info "Demande de certificat SSL avec Let's Encrypt (mode manuel)..."
print_info "Vous allez devoir ajouter un enregistrement TXT à votre zone DNS."
print_info "Suivez attentivement les instructions qui vont s'afficher."
echo ""

# Demande de certificat pour le domaine principal et le sous-domaine www
docker compose run --rm certbot certonly --manual --preferred-challenges=dns \
    --email $EMAIL \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    -d $DOMAIN_NAME -d www.$DOMAIN_NAME

if [ $? -ne 0 ]; then
    print_error "Échec de l'obtention du certificat SSL."
    print_info "Vous pouvez essayer à nouveau en exécutant: "
    print_info "docker compose run --rm certbot certonly --manual --preferred-challenges=dns --email $EMAIL --server https://acme-v02.api.letsencrypt.org/directory --agree-tos -d $DOMAIN_NAME -d www.$DOMAIN_NAME"
    
    # Continuer sans HTTPS
    print_info "Démarrage des conteneurs sans HTTPS..."
    docker compose down
    
    # Modifier la configuration Nginx pour fonctionner sans HTTPS
    cat > server/default.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    root /var/www/public;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF
    
    # Modifier compose.yml pour exposer uniquement le port 80
    sed -i 's/- "443:443"/#- "443:443"/g' compose.yml
    
    docker compose up -d
else
    print_success "Certificat SSL obtenu avec succès."
    
    # Redémarrer les conteneurs pour appliquer les changements
    print_info "Redémarrage des conteneurs avec SSL..."
    docker compose down
    docker compose up -d
fi

# Exécuter les commandes Laravel nécessaires
print_header "CONFIGURATION FINALE LARAVEL"
print_info "Exécution des commandes Laravel nécessaires..."

print_info "Installation des dépendances Composer..."
docker exec -it timesheet-manager composer install --no-dev --optimize-autoloader

print_info "Génération de la clé d'application..."
docker exec -it timesheet-manager php artisan key:generate --force

print_info "Création de la table des sessions..."
docker exec -it timesheet-manager php artisan session:table || true
docker exec -it timesheet-manager php artisan migrate --force

print_info "Nettoyage des caches..."
docker exec -it timesheet-manager php artisan cache:clear
docker exec -it timesheet-manager php artisan config:clear
docker exec -it timesheet-manager php artisan view:clear
docker exec -it timesheet-manager php artisan route:clear

print_info "Installation et compilation des assets frontend..."
docker exec -it timesheet-manager npm install
docker exec -it timesheet-manager npm run build

print_info "Définition des permissions..."
docker exec -it timesheet-manager sh -c "chmod -R 775 /var/www/storage /var/www/bootstrap/cache && chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache"

# Vérifier que le resolver DNS est présent dans la configuration nginx
print_header "VÉRIFICATION DE LA CONFIGURATION NGINX"
if ! grep -q "resolver" server/default.conf; then
    print_info "Ajout d'un resolver DNS à la configuration Nginx pour l'OCSP stapling..."
    sed -i '1i resolver 1.1.1.1 8.8.8.8 valid=300s;\nresolver_timeout 5s;' server/default.conf
    docker compose restart nginx
    print_success "Configuration Nginx mise à jour et service redémarré."
fi

# Afficher les informations de connexion
print_header "DÉPLOIEMENT TERMINÉ"
print_success "Votre application Laravel est maintenant déployée et configurée!"

if [ $? -eq 0 ]; then
    print_info "Votre application Laravel est accessible à l'adresse:"
    echo "- HTTP: http://$DOMAIN_NAME (redirigé vers HTTPS)"
    echo "- HTTPS: https://$DOMAIN_NAME"
fi

print_info "PgAdmin est accessible à l'adresse: http://$DOMAIN_NAME:5050"
echo "Email: $EMAIL"
echo "Mot de passe: $PGADMIN_PASSWORD"
echo ""

print_info "Informations de connexion à la base de données PostgreSQL:"
echo "- Hôte: db"
echo "- Port: 5432"
echo "- Base de données: $DB_NAME"
echo "- Utilisateur: $DB_USER"
echo "- Mot de passe: $DB_PASSWORD"
echo ""

print_info "Important: N'oubliez pas de configurer la redirection de port sur votre routeur!"
echo "- Le port 80 doit être redirigé vers le port 80 de ce serveur"
echo "- Le port 443 doit être redirigé vers le port 443 de ce serveur"
echo ""

print_info "Pour modifier votre application, vous pouvez:"
echo "1. Modifier les fichiers dans le dossier 'www'"
echo "2. Reconstruire l'image Docker avec: docker compose build app"
echo "3. Redémarrer les conteneurs avec: docker compose restart"
echo ""

print_info "Pour afficher les logs de votre application, utilisez:"
echo "docker compose logs -f app"
echo ""

print_info "Pour redémarrer tous les services:"
echo "docker compose down && docker compose up -d"