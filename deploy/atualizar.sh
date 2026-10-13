#!/usr/bin/env bash
# Atualiza a aplicação já instalada: git pull, copia o código, instala
# dependências, aplica migrações, coleta estáticos e reinicia o serviço.
#
# Uso (na VM, dentro do clone):
#   sudo ./deploy/atualizar.sh            # faz git pull antes
#   sudo ./deploy/atualizar.sh --sem-pull # usa o código como está
set -euo pipefail
source "$(dirname "$0")/comum.sh"

[ -x $BASE/venv/bin/python ] && [ -f $ENV_FILE ] || erro "aplicação não instalada. Rode deploy/instalar.sh primeiro."

if [ "${1:-}" != "--sem-pull" ]; then
    log "Atualizando o repositório (git pull)"
    DONO="$(stat -c %U "$REPO")"
    runuser -u "$DONO" -- git -C "$REPO" pull --ff-only
fi

log "Copiando código para $BASE/app"
rsync -a --delete \
    --exclude=.git/ --exclude=.venv/ --exclude=.cache/ --exclude=deploy/ \
    --exclude=__pycache__/ --exclude='*.pyc' \
    --exclude=db.sqlite3 --exclude=staticfiles/ \
    "$REPO"/ $BASE/app/
chown -R root:root $BASE/app
chmod -R u=rwX,go=rX $BASE/app

log "Instalando dependências Python"
$BASE/venv/bin/pip install -q --upgrade pip
$BASE/venv/bin/pip install -q -r $BASE/app/requirements.txt

log "Migrações e arquivos estáticos"
$MANAGE migrate --noinput
$MANAGE collectstatic --noinput --clear -v 0
$MANAGE check

log "Reiniciando $SERVICO"
systemctl restart $SERVICO
sleep 2
if ! systemctl is-active --quiet $SERVICO; then
    journalctl -u $SERVICO -n 30 --no-pager
    erro "serviço $SERVICO não está rodando."
fi
log "Aplicação atualizada ($(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || echo 'sem git'))"
