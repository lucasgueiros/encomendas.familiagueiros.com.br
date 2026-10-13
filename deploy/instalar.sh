#!/usr/bin/env bash
# Instala a aplicação nesta VM (nginx já existente, sem Docker), com HTTPS.
# Pode ser rodado de novo sem problemas (não apaga banco nem SECRET_KEY).
#
# Uso (na VM, dentro do clone do git):
#   sudo ./deploy/instalar.sh
#
# Variáveis opcionais:
#   DOMINIO        (padrão: encomendas.familiagueiros.com.br)
#   APP_PORTA      porta local do gunicorn (padrão: 8010)
#   CERTBOT_EMAIL  e-mail para avisos do Let's Encrypt
#   ex.: sudo CERTBOT_EMAIL=voce@exemplo.com ./deploy/instalar.sh
#
# Para atualizar depois: sudo ./deploy/atualizar.sh
set -euo pipefail
source "$(dirname "$0")/comum.sh"

DOMINIO="${DOMINIO:-encomendas.familiagueiros.com.br}"
PORTA="${APP_PORTA:-8010}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
WEBROOT=/var/www/certbot

command -v nginx >/dev/null || erro "nginx não encontrado."

# ---------------------------------------------------------------- pacotes
log "Instalando dependências do sistema"
if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq python3 python3-venv certbot rsync curl git >/dev/null
else
    for c in python3 certbot rsync curl git; do
        command -v $c >/dev/null || erro "instale '$c' manualmente (sistema sem apt)."
    done
fi

# Django 6.x exige Python >= 3.12
PYTHON=""
for c in python3.14 python3.13 python3.12 python3; do
    if command -v $c >/dev/null && $c -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
        PYTHON="$(command -v $c)"
        break
    fi
done
[ -n "$PYTHON" ] || erro "Python >= 3.12 não encontrado (Django 6 exige). Instale um (ex.: python3.12) e rode de novo."
echo "Usando $PYTHON ($($PYTHON --version))"

# ---------------------------------------------------------------- usuário e diretórios
log "Preparando usuário e diretórios"
id -u $USUARIO >/dev/null 2>&1 || useradd --system --home-dir $DADOS --shell /usr/sbin/nologin $USUARIO
install -d -o root -g root -m 755 $BASE $BASE/app
install -d -o $USUARIO -g $USUARIO -m 755 $BASE/static
install -d -o $USUARIO -g $USUARIO -m 750 $DADOS $DADOS/cache
install -d -o root -g $USUARIO -m 750 $ENV_DIR
install -d -m 755 $WEBROOT

# ---------------------------------------------------------------- virtualenv
log "Criando virtualenv"
if [ ! -x $BASE/venv/bin/python ] || ! $BASE/venv/bin/python -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
    rm -rf $BASE/venv
    if ! "$PYTHON" -m venv $BASE/venv; then
        command -v apt-get >/dev/null && apt-get install -y -qq "$(basename "$PYTHON")-venv" >/dev/null
        "$PYTHON" -m venv $BASE/venv
    fi
fi

# ---------------------------------------------------------------- variáveis de ambiente
if [ ! -f $ENV_FILE ]; then
    log "Criando $ENV_FILE (SECRET_KEY nova)"
    cat > $ENV_FILE <<EOF
DJANGO_SETTINGS_MODULE=config.settings
DJANGO_SECRET_KEY=$($PYTHON -c 'import secrets; print(secrets.token_urlsafe(50))')
DJANGO_DEBUG=0
DJANGO_ALLOWED_HOSTS=$DOMINIO
DJANGO_CSRF_TRUSTED_ORIGINS=https://$DOMINIO
DJANGO_HTTPS=1
DJANGO_DB_PATH=$DADOS/db.sqlite3
DJANGO_CACHE_DIR=$DADOS/cache
DJANGO_STATIC_ROOT=$BASE/static
CONSULTA_USAR_X_FORWARDED_FOR=1
EOF
else
    log "Mantendo $ENV_FILE existente"
fi
chown root:$USUARIO $ENV_FILE
chmod 640 $ENV_FILE

# Atalho para rodar manage.py como o usuário da aplicação:
#   sudo encomendas-manage createsuperuser
cat > $MANAGE <<EOF
#!/usr/bin/env bash
cd $BASE/app
exec runuser -u $USUARIO -- bash -c 'set -a; . $ENV_FILE; set +a; exec $BASE/venv/bin/python $BASE/app/manage.py "\$@"' _ "\$@"
EOF
chmod 755 $MANAGE

# ---------------------------------------------------------------- gunicorn (systemd)
log "Configurando serviço systemd ($SERVICO na porta $PORTA)"
if ! systemctl is-active --quiet $SERVICO && ss -ltn "sport = :$PORTA" | grep -q LISTEN; then
    erro "porta $PORTA já está em uso. Rode de novo com APP_PORTA=<outra porta>."
fi
cat > /etc/systemd/system/$SERVICO <<EOF
[Unit]
Description=Encomendas (Django/gunicorn)
After=network.target

[Service]
Type=simple
User=$USUARIO
Group=$USUARIO
WorkingDirectory=$BASE/app
EnvironmentFile=$ENV_FILE
ExecStart=$BASE/venv/bin/gunicorn config.wsgi:application --bind 127.0.0.1:$PORTA --workers 2 --access-logfile - --error-logfile -
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$DADOS

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --quiet $SERVICO

# Copia o código, instala dependências, migra e (re)inicia o serviço.
"$REPO/deploy/atualizar.sh" --sem-pull

# ---------------------------------------------------------------- nginx
if [ -d /etc/nginx/sites-available ]; then
    CONF=/etc/nginx/sites-available/$DOMINIO
    LINK=/etc/nginx/sites-enabled/$DOMINIO
else
    CONF=/etc/nginx/conf.d/$DOMINIO.conf
    LINK=""
fi
CERT_DIR=/etc/letsencrypt/live/$DOMINIO

BLOCO_APP="
    client_max_body_size 10m;

    location /static/ {
        alias $BASE/static/;
        expires 7d;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:$PORTA;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 60s;
    }"

escrever_nginx() {  # $1 = http | https
    if [ "$1" = http ]; then
        cat > $CONF <<EOF
# Gerado por deploy/servidor.sh — será sobrescrito no próximo deploy.
server {
    listen 80;
    listen [::]:80;
    server_name $DOMINIO;

    location /.well-known/acme-challenge/ { root $WEBROOT; }
$BLOCO_APP
}
EOF
    else
        cat > $CONF <<EOF
# Gerado por deploy/servidor.sh — será sobrescrito no próximo deploy.
server {
    listen 80;
    listen [::]:80;
    server_name $DOMINIO;

    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $DOMINIO;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header Strict-Transport-Security "max-age=31536000" always;
$BLOCO_APP
}
EOF
    fi
    [ -n "$LINK" ] && ln -sf $CONF $LINK
}

aplicar_nginx() {  # $1 = http | https; restaura a config anterior se nginx -t falhar
    local backup=""
    if [ -f $CONF ]; then backup=$(mktemp); cp $CONF "$backup"; fi
    escrever_nginx "$1"
    if ! nginx -t 2>/tmp/nginx-test.log; then
        cat /tmp/nginx-test.log >&2
        if [ -n "$backup" ]; then cp "$backup" $CONF; else rm -f $CONF ${LINK:-}; fi
        erro "configuração do nginx inválida; config anterior restaurada."
    fi
    [ -n "$backup" ] && rm -f "$backup"
    systemctl reload nginx
}

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
fi

# ---------------------------------------------------------------- HTTPS (Let's Encrypt)
if [ ! -f $CERT_DIR/fullchain.pem ]; then
    log "Obtendo certificado Let's Encrypt para $DOMINIO"
    aplicar_nginx http
    if [ -n "$CERTBOT_EMAIL" ]; then CONTATO=(--email "$CERTBOT_EMAIL"); else CONTATO=(--register-unsafely-without-email); fi
    certbot certonly --webroot -w $WEBROOT -d $DOMINIO --cert-name $DOMINIO \
        --non-interactive --agree-tos "${CONTATO[@]}" \
        || erro "certbot falhou. Verifique se $DOMINIO resolve para o IP desta VM e se a porta 80 está aberta."
fi

# Recarrega o nginx quando o certificado for renovado (o timer do certbot renova sozinho).
install -d /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

log "Ativando HTTPS no nginx"
aplicar_nginx https

# ---------------------------------------------------------------- verificação
CODIGO=$(curl -s -o /dev/null -w '%{http_code}' --resolve "$DOMINIO:443:127.0.0.1" "https://$DOMINIO/" || true)
log "Publicado: https://$DOMINIO/ (resposta local: HTTP $CODIGO)"
echo "Logs:          sudo journalctl -u $SERVICO -f"
echo "Criar admin:   sudo $APP-manage createsuperuser"
echo "Atualizar:     sudo ./deploy/atualizar.sh"
