#!/bin/bash

# --- Variáveis do banco de dados ---
DB_USERNAME="solidtime"
DB_DATABASE="solidtime"

# --- Configurações ---
CONTAINER_NAME="0-docker-traefik-with-database-database-1" # Verifique o nome do seu contêiner com 'docker ps' se for diferente
BACKUP_DIR="/home/leonardo/Documentos/Backups/Solidtime" # <-- MUDAR ESTE CAMINHO PARA SUA PASTA REAL!

# Nome do arquivo de backup com timestamp
BACKUP_FILE="${BACKUP_DIR}/solidtime_backup_$(date +%Y%m%d_%H%M%S).sql"

# --- Função para enviar notificação de sistema ---
send_notification() {
    local type="$1" # "SUCCESS" ou "ERROR"
    local message="$2"
    local title="Backup SolidTime DB"

    # Use notify-send se disponível para notificações na área de trabalho
    if command -v notify-send &> /dev/null; then
        if [ "$type" == "SUCCESS" ]; then
            notify-send -i checkbox "$title" "$message"
        else
            notify-send -u critical -i dialog-error "$title" "$message"
        fi
    # Adicione aqui outros métodos de notificação se necessário (ex: logstash, Slack, etc.)
    fi
}

# --- Validação das variáveis de ambiente ---
if [ -z "${DB_USERNAME}" ] || [ -z "${DB_DATABASE}" ]; then
    ERROR_MSG="Erro: As variáveis de ambiente DB_USERNAME e DB_DATABASE devem estar definidas."
    echo "${ERROR_MSG}" >&2 # Imprime no erro padrão
    send_notification "ERROR" "${ERROR_MSG}"
    exit 1
fi

# Nota sobre a senha: pg_dump geralmente precisa da senha.
# A maneira mais segura é definir a variável de ambiente PGPASSWORD antes de executar este script,
# ou configurar um arquivo ~/.pgpass. Não é recomendado passar a senha diretamente na linha de comando por segurança.
# Ex: export PGPASSWORD="sua_senha_aqui"
# Ou adicione no seu .env que é carregado antes de rodar o script.

# --- Validação do diretório de backup ---
if [ ! -d "${BACKUP_DIR}" ]; then
    ERROR_MSG="Erro: Diretório de backup '${BACKUP_DIR}' não encontrado."
    echo "${ERROR_MSG}" >&2
    send_notification "ERROR" "${ERROR_MSG}"
    exit 1
fi

if [ ! -w "${BACKUP_DIR}" ]; then
    ERROR_MSG="Erro: Sem permissão de escrita no diretório de backup '${BACKUP_DIR}'."
    echo "${ERROR_MSG}" >&2
    send_notification "ERROR" "${ERROR_MSG}"
    exit 1
fi

# --- Validação do contêiner ---
# Verifica se o contêiner existe E está rodando (status 'running')
if ! docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q "running"; then
    ERROR_MSG="Erro: Contêiner Docker '${CONTAINER_NAME}' não encontrado ou não está rodando."
    echo "${ERROR_MSG}" >&2
    send_notification "ERROR" "${ERROR_MSG}"
    exit 1
fi

# --- Executar o backup ---
echo "Iniciando backup do banco de dados '${DB_DATABASE}' do contêiner '${CONTAINER_NAME}'..."
echo "Salvando em: ${BACKUP_FILE}"

# Executa pg_dump dentro do contêiner e salva a saída no arquivo local
if docker exec -t "${CONTAINER_NAME}" pg_dump -U "${DB_USERNAME}" "${DB_DATABASE}" > "${BACKUP_FILE}"; then
    SUCCESS_MSG="Backup do banco de dados '${DB_DATABASE}' concluído com sucesso!"
    echo "${SUCCESS_MSG}"
    send_notification "SUCCESS" "${SUCCESS_MSG}"
    exit 0
else
    ERROR_MSG="Erro: Falha ao executar pg_dump no contêiner '${CONTAINER_NAME}'. Verifique os logs do contêiner para mais detalhes."
    echo "${ERROR_MSG}" >&2
    send_notification "ERROR" "${ERROR_MSG}"
    # Opcional: Remover arquivo de backup parcial se a falha ocorreu durante a escrita
    if [ -f "${BACKUP_FILE}" ]; then rm "${BACKUP_FILE}"; fi
    exit 1
fi
