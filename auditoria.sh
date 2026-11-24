#!/usr/bin/env bash
# Auditoria básica de servidor Linux
# Uso: bash auditoria.sh [diretorio_destino]
# E-mail opcional: AUDIT_EMAIL=destino@exemplo.com bash auditoria.sh [diretorio]

set -u

# Define o diretório e o nome do relatório, permitindo informar um destino na execução.
DESTINO="${1:-.}"
ARQUIVO="${DESTINO%/}/auditoria_servidor.txt"

# Prepara o destino e valida antecipadamente que o relatório pode ser criado.
if ! mkdir -p -- "$DESTINO" 2>/dev/null; then
  printf 'Erro: não foi possível criar/acessar o diretório: %s\n' "$DESTINO" >&2
  exit 1
fi
if ! : > "$ARQUIVO" 2>/dev/null; then
  printf 'Erro: não foi possível gravar o relatório: %s\n' "$ARQUIVO" >&2
  exit 1
fi

# Cores para mensagens exibidas no terminal; o relatório mantém texto simples.
VERDE='\033[0;32m'; AZUL='\033[0;34m'; AMARELO='\033[0;33m'; VERMELHO='\033[0;31m'; RESET='\033[0m'

# Helpers para mensagens, títulos de seção, gravação e checagem de comandos.
log() { printf "${AZUL}[*] %s${RESET}\n" "$*"; }
secao() {
  printf '\n\n======================================================================\n' >> "$ARQUIVO"
  printf '%s\n' "$1" >> "$ARQUIVO"
  printf '======================================================================\n' >> "$ARQUIVO"
  printf "${VERDE}[+] %s${RESET}\n" "$1"
}
linha() { printf '%s\n' "$*" >> "$ARQUIVO"; }
comando_disponivel() { command -v "$1" >/dev/null 2>&1; }
coletar() {
  # Executa um comando e registra a saída; não interrompe a auditoria em caso de falha.
  local descricao="$1"; shift
  linha "--- $descricao ---"
  if "$@" >> "$ARQUIVO" 2>&1; then :; else linha "[Indisponível ou sem permissão para executar: $*]"; fi
  linha ""
}

# Registra no início do arquivo o contexto básico da execução da auditoria.
{
  echo 'RELATÓRIO DE AUDITORIA DO SERVIDOR'
  echo "Gerado em: $(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo 'data indisponível')"
  echo "Host: $(hostname 2>/dev/null || echo 'indisponível')"
  echo "Executado por: $(id -un 2>/dev/null || echo 'indisponível')"
  echo 'Observação: informações restritas podem exigir execução com sudo/root.'
} >> "$ARQUIVO"

log 'Iniciando auditoria. O relatório será salvo em: '"$ARQUIVO"

# Coleta identificação do host, distribuição, kernel, horário e tempo ligado.
secao 'SEÇÃO 1 — IDENTIDADE DA MÁQUINA'
coletar 'Hostname' hostname
if [ -r /etc/os-release ]; then
  linha 'Sistema operacional:'
  . /etc/os-release
  linha "${PRETTY_NAME:-Distribuição não identificada}"
else linha 'Sistema operacional: /etc/os-release indisponível'; fi
coletar 'Versão do kernel' uname -a
coletar 'Data e hora atual' date
coletar 'Uptime' uptime
coletar 'Arquitetura do processador' uname -m

# Resume recursos de hardware e capacidade/uso de memória, swap e discos.
secao 'SEÇÃO 2 — HARDWARE E RECURSOS'
if comando_disponivel lscpu; then coletar 'Informações de CPU' lscpu; else coletar 'CPU (resumo)' grep -m 1 'model name' /proc/cpuinfo; fi
linha 'Quantidade de CPUs:'
if comando_disponivel nproc; then nproc >> "$ARQUIVO" 2>&1 || linha '[indisponível]'; else linha '[comando nproc indisponível]'; fi
coletar 'Memória RAM (total, usada e disponível)' free -h
coletar 'Uso de disco por partição' df -hT
coletar 'Informações de swap' swapon --show
if ! comando_disponivel swapon; then linha 'Comando swapon indisponível.'; fi

# Registra interfaces, rotas, portas em escuta e configuração de DNS.
secao 'SEÇÃO 3 — REDE'
coletar 'Endereços IP de todas as interfaces' ip -brief address
coletar 'Tabela de rotas' ip route show
if comando_disponivel ss; then
  linha '--- Portas TCP/UDP em escuta e processos ---'
  if ss -tulpen >> "$ARQUIVO" 2>&1; then :; else linha '[Falha ao consultar sockets; tente executar com sudo.]'; fi
elif comando_disponivel netstat; then coletar 'Portas em escuta e processos' netstat -tulpen
else linha 'Não foi encontrado ss nem netstat.'; fi
linha ''
linha '--- Configuração DNS ---'
if [ -r /etc/resolv.conf ]; then cat /etc/resolv.conf >> "$ARQUIVO"; else linha '/etc/resolv.conf indisponível'; fi

# Lista processos com maior consumo e verifica serviços habilitados e ativos.
secao 'SEÇÃO 4 — PROCESSOS E SERVIÇOS'
if comando_disponivel ps; then
  linha '--- Top 5 processos por consumo de CPU ---'
  ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 6 >> "$ARQUIVO" || linha '[indisponível]'
  linha ''
  linha '--- Top 5 processos por consumo de memória ---'
  ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%mem 2>/dev/null | head -n 6 >> "$ARQUIVO" || linha '[indisponível]'
else linha 'Comando ps indisponível.'; fi
if comando_disponivel systemctl; then
  coletar 'Serviços habilitados no systemd (inicialização)' systemctl list-unit-files --type=service --state=enabled --no-pager
  coletar 'Serviços atualmente ativos/rodando' systemctl list-units --type=service --state=running --no-pager
else linha 'systemctl indisponível (sistema pode não usar systemd).'; fi

# Examina contas interativas e configurações relacionadas ao acesso SSH.
secao 'SEÇÃO 5 — USUÁRIOS E SEGURANÇA'
linha '--- Usuários com shell interativo (shell diferente de nologin/false) ---'
if [ -r /etc/passwd ]; then
  awk -F: '($7 !~ /(nologin|false)$/ && $7 != "") {printf "usuário=%s uid=%s home=%s shell=%s\n",$1,$3,$6,$7}' /etc/passwd >> "$ARQUIVO"
else linha '/etc/passwd indisponível'; fi
linha ''
coletar 'Últimos logins registrados por usuário' lastlog
linha '--- Login SSH do root ---'
if comando_disponivel sshd; then
  SSH_ROOT=$(sshd -T 2>/dev/null | awk '$1=="permitrootlogin" {print $2; exit}')
  if [ -n "$SSH_ROOT" ]; then linha "PermitRootLogin efetivo: $SSH_ROOT"; else linha 'Não foi possível obter PermitRootLogin via sshd -T (pode exigir privilégios ou configuração válida).'; fi
elif [ -r /etc/ssh/sshd_config ]; then
  ROOT_CFG=$(awk 'tolower($1)=="permitrootlogin" {v=$2} END {if(v!="") print v}' /etc/ssh/sshd_config)
  linha "Diretiva PermitRootLogin encontrada no arquivo principal: ${ROOT_CFG:-não definida (verifique Includes e padrões do OpenSSH)}"
else linha 'sshd e configuração SSH não encontrados.'; fi
linha ''
linha '--- Chaves SSH autorizadas do usuário que executou o script ---'
HOME_ATUAL="${HOME:-}"
if [ -n "$HOME_ATUAL" ] && [ -r "$HOME_ATUAL/.ssh/authorized_keys" ]; then
  # Exibe fingerprints em vez do conteúdo das chaves, reduzindo exposição de dados.
  if comando_disponivel ssh-keygen; then
    ssh-keygen -lf "$HOME_ATUAL/.ssh/authorized_keys" >> "$ARQUIVO" 2>&1 || linha '[Não foi possível calcular fingerprints.]'
  else
    awk 'NF && $1 !~ /^#/ {print "Tipo de chave: " $1 " (fingerprint indisponível sem ssh-keygen)"}' "$HOME_ATUAL/.ssh/authorized_keys" >> "$ARQUIVO"
  fi
else linha 'Nenhum arquivo authorized_keys legível encontrado para o usuário atual.'; fi

# Reúne logs recentes e procura registros comuns de falhas de autenticação.
secao 'SEÇÃO 6 — LOGS RECENTES'
if comando_disponivel journalctl; then
  coletar 'Últimas 20 linhas do journal' journalctl -n 20 --no-pager
elif [ -r /var/log/syslog ]; then
  linha '--- Últimas 20 linhas de /var/log/syslog ---'
  tail -n 20 /var/log/syslog >> "$ARQUIVO" 2>&1 || linha '[falha ao ler syslog]'
elif [ -r /var/log/messages ]; then
  linha '--- Últimas 20 linhas de /var/log/messages ---'
  tail -n 20 /var/log/messages >> "$ARQUIVO" 2>&1 || linha '[falha ao ler messages]'
else linha 'journalctl, syslog e messages indisponíveis ou sem permissão.'; fi
linha ''
linha '--- Falhas recentes de autenticação/SSH (quando disponíveis) ---'
if comando_disponivel journalctl; then
  journalctl --since '7 days ago' --no-pager 2>/dev/null | grep -Ei 'failed password|authentication failure|invalid user|failed publickey' | tail -n 50 >> "$ARQUIVO" || linha 'Nenhuma ocorrência encontrada ou logs sem acesso.'
elif [ -r /var/log/auth.log ]; then
  grep -Ei 'failed password|authentication failure|invalid user|failed publickey' /var/log/auth.log | tail -n 50 >> "$ARQUIVO" || linha 'Nenhuma ocorrência encontrada.'
elif [ -r /var/log/secure ]; then
  grep -Ei 'failed password|authentication failure|invalid user|failed publickey' /var/log/secure | tail -n 50 >> "$ARQUIVO" || linha 'Nenhuma ocorrência encontrada.'
else linha 'Log de autenticação não encontrado ou sem permissão.'; fi

# Consulta atualizações disponíveis quando o gerenciador APT está instalado.
secao 'VERIFICAÇÕES ADICIONAIS — ATUALIZAÇÕES DE SEGURANÇA'
if comando_disponivel apt; then
  linha 'Pacotes atualizáveis (apt list --upgradable). A saída não identifica exclusivamente atualizações de segurança:'
  apt list --upgradable 2>/dev/null >> "$ARQUIVO" || linha '[Não foi possível consultar pacotes; talvez seja necessário atualizar o índice ou usar sudo.]'
else linha 'APT não encontrado; verificação específica para Debian/Ubuntu não aplicável.'; fi

# Compara uso atual de disco e RAM com limites definidos e registra alertas.
secao 'ALERTAS AUTOMÁTICOS'
ALERTA=0
if comando_disponivel df; then
  while IFS= read -r uso; do
    [ -z "$uso" ] && continue
    pct="${uso%% *}"
    if [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -gt 80 ]; then
      linha "[ALERTA] Uso de disco acima de 80%: $uso"
      printf "${VERMELHO}[ALERTA] Disco acima de 80%%: %s${RESET}\n" "$uso"
      ALERTA=1
    fi
  done < <(df -P -x tmpfs -x devtmpfs 2>/dev/null | awk 'NR>1 {print $5 " em " $6}')
fi
if comando_disponivel free; then
  MEM_PCT=$(free | awk '/Mem:/ {if ($2>0) printf "%d", ($3/$2)*100}')
  if [[ "$MEM_PCT" =~ ^[0-9]+$ ]] && [ "$MEM_PCT" -gt 90 ]; then
    linha "[ALERTA] Uso de RAM acima de 90%: ${MEM_PCT}%"
    printf "${VERMELHO}[ALERTA] RAM acima de 90%%: %s%%${RESET}\n" "$MEM_PCT"
    ALERTA=1
  fi
fi
if [ "$ALERTA" -eq 0 ]; then linha 'Nenhum alerta de disco (>80%) ou RAM (>90%) detectado no momento.'; printf "${VERDE}[+] Nenhum alerta de recursos detectado.${RESET}\n"; fi

linha ''
linha 'FIM DO RELATÓRIO'
linha "Gerado em: $(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo 'indisponível')"
printf "${VERDE}[+] Auditoria concluída. Relatório: %s${RESET}\n" "$ARQUIVO"

# Se configurado explicitamente, tenta enviar o relatório pelo mail ou sendmail.
if [ -n "${AUDIT_EMAIL:-}" ]; then
  if comando_disponivel mail; then
    if mail -s "Auditoria do servidor $(hostname 2>/dev/null)" "$AUDIT_EMAIL" < "$ARQUIVO"; then
      printf "${VERDE}[+] Relatório enviado para %s usando mail.${RESET}\n" "$AUDIT_EMAIL"
    else printf "${AMARELO}[!] Falha ao enviar e-mail com mail.${RESET}\n"; fi
  elif comando_disponivel sendmail; then
    {
      printf 'To: %s\n' "$AUDIT_EMAIL"
      printf 'Subject: Auditoria do servidor %s\n' "$(hostname 2>/dev/null)"
      printf 'MIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\n\n'
      cat "$ARQUIVO"
    } | sendmail -t
    printf "${VERDE}[+] Solicitação de envio entregue ao sendmail.${RESET}\n"
  else printf "${AMARELO}[!] AUDIT_EMAIL definido, mas mail/sendmail não está instalado.${RESET}\n"; fi
fi
