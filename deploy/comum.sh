# Variáveis e funções compartilhadas por instalar.sh e atualizar.sh.
#
# Layout na VM:
#   <clone do git>                   de onde o código é copiado
#   /opt/encomendas/app              cópia do código que roda em produção
#   /opt/encomendas/venv             virtualenv
#   /opt/encomendas/static           arquivos estáticos (servidos pelo nginx)
#   /var/lib/encomendas              banco SQLite e cache (preservados entre deploys)
#   /etc/encomendas/encomendas.env   variáveis de ambiente (SECRET_KEY etc.)

APP=encomendas
USUARIO=encomendas
BASE=/opt/$APP
DADOS=/var/lib/$APP
ENV_DIR=/etc/$APP
ENV_FILE=$ENV_DIR/$APP.env
SERVICO=$APP.service
MANAGE=/usr/local/bin/$APP-manage
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
erro() { echo -e "\033[1;31mERRO: $*\033[0m" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || erro "rode com sudo."
[ -f "$REPO/manage.py" ] || erro "manage.py não encontrado em $REPO."
