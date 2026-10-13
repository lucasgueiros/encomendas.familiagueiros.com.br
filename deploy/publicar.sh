#!/usr/bin/env bash
# Publica a aplicação na VM (sem Docker): envia o código via SSH e roda
# deploy/servidor.sh lá com sudo.
#
# Uso:
#   ./deploy/publicar.sh usuario@ip-ou-host-da-vm
#
# Variáveis opcionais:
#   DOMINIO        (padrão: encomendas.familiagueiros.com.br)
#   APP_PORTA      porta local do gunicorn na VM (padrão: 8010)
#   CERTBOT_EMAIL  e-mail para avisos do Let's Encrypt (só usado no 1º certificado)
set -euo pipefail

DESTINO="${1:-${DEPLOY_HOST:-}}"
if [ -z "$DESTINO" ]; then
    echo "uso: $0 usuario@vm" >&2
    exit 1
fi

DOMINIO="${DOMINIO:-encomendas.familiagueiros.com.br}"
APP_PORTA="${APP_PORTA:-8010}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="encomendas-deploy"  # relativo ao home do usuário remoto

echo "==> Enviando código para $DESTINO:~/$STAGING"
tar -C "$RAIZ" -czf - \
    --exclude=.venv --exclude=.cache --exclude=.git --exclude=.claude \
    --exclude=__pycache__ --exclude='*.pyc' \
    --exclude=db.sqlite3 --exclude=staticfiles \
    . | ssh "$DESTINO" "rm -rf ~/$STAGING && mkdir -p ~/$STAGING && tar -xzf - -C ~/$STAGING"

echo "==> Configurando o servidor (pode pedir a senha do sudo)"
ssh -t "$DESTINO" "sudo bash ~/$STAGING/deploy/servidor.sh ~/$STAGING '$DOMINIO' '$APP_PORTA' '$CERTBOT_EMAIL'"
