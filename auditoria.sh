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
coletar_falhas_auth() {
  local fonte="$1"; shift
  local -a status
  "$@" | grep -Ei 'failed password|authentication failure|invalid user|failed publickey' | tail -n 50 >> "$ARQUIVO"
  status=("${PIPESTATUS[@]}")
  if [ "${status[0]}" -ne 0 ]; then
    linha "[Não foi possível consultar os logs de autenticação em $fonte.]"
  elif [ "${status[1]}" -eq 1 ]; then
    linha 'Nenhuma falha de autenticação correspondente foi encontrada nos logs consultados.'
  elif [ "${status[1]}" -ne 0 ] || [ "${status[2]}" -ne 0 ]; then
    linha "[Falha ao filtrar ou registrar os logs de autenticação em $fonte.]"
  fi
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
  ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | awk -v auditoria_pid="$$" 'NR == 1 || $1 != auditoria_pid' | head -n 6 >> "$ARQUIVO" || linha '[indisponível]'
  linha ''
  linha '--- Top 5 processos por consumo de memória ---'
  ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%mem 2>/dev/null | awk -v auditoria_pid="$$" 'NR == 1 || $1 != auditoria_pid' | head -n 6 >> "$ARQUIVO" || linha '[indisponível]'
else linha 'Comando ps indisponível.'; fi
if comando_disponivel systemctl; then
  coletar 'Serviços habilitados no systemd (inicialização)' systemctl list-unit-files --type=service --state=enabled --no-pager
  coletar 'Serviços atualmente ativos/rodando' systemctl list-units --type=service --state=running --no-pager
else linha 'systemctl indisponível (sistema pode não usar systemd).'; fi

# Examina contas interativas e configurações relacionadas ao acesso SSH.
secao 'SEÇÃO 5 — USUÁRIOS E SEGURANÇA'
UID_MIN=$(awk '$1 == "UID_MIN" {print $2; exit}' /etc/login.defs 2>/dev/null)
if ! [[ "$UID_MIN" =~ ^[0-9]+$ ]]; then UID_MIN=1000; fi
linha "Classificação aproximada por UID_MIN de /etc/login.defs (fallback: 1000): $UID_MIN"
linha "--- Contas de usuário (UID >= $UID_MIN) com shell interativo ---"
if [ -r /etc/passwd ]; then
  awk -F: -v min="$UID_MIN" '($3 + 0 >= min && $7 != "" && $7 !~ /(nologin|false|sync|shutdown|halt)$/) {printf "usuário=%s uid=%s home=%s shell=%s\n",$1,$3,$6,$7}' /etc/passwd >> "$ARQUIVO"
  linha ''
  linha "--- Contas de sistema/serviço (UID > 0 e < $UID_MIN), inclusive sem shell interativo ---"
  awk -F: -v min="$UID_MIN" '($3 + 0 > 0 && $3 + 0 < min) {printf "conta=%s uid=%s home=%s shell=%s\n",$1,$3,$6,$7}' /etc/passwd >> "$ARQUIVO"
  linha ''
  linha '--- Contas administrativas (UID 0) ---'
  awk -F: '($3 + 0 == 0) {printf "conta=%s uid=%s home=%s shell=%s\n",$1,$3,$6,$7}' /etc/passwd >> "$ARQUIVO"
else linha '/etc/passwd indisponível'; fi
linha ''
if comando_disponivel lastlog; then
  coletar 'Últimos logins registrados por usuário' lastlog
elif comando_disponivel last; then
  linha 'lastlog não está instalado; usando last como alternativa (histórico wtmp disponível):'
  if last -F -w >> "$ARQUIVO" 2>&1; then :; else linha '[Não foi possível consultar o histórico de logins com last.]'; fi
else
  linha 'Verificação de último login indisponível: nem lastlog nem last estão instalados.'
fi
linha '--- Login SSH do root ---'
SSHD_BIN=$(command -v sshd 2>/dev/null || true)
if [ -z "$SSHD_BIN" ]; then
  for candidato in /usr/sbin/sshd /sbin/sshd; do
    if [ -x "$candidato" ]; then SSHD_BIN="$candidato"; break; fi
  done
fi
if [ -n "$SSHD_BIN" ]; then
  if SSH_CONFIG_EFETIVA=$("$SSHD_BIN" -T -C "user=root,host=localhost,addr=127.0.0.1" 2>/dev/null); then
    SSH_ROOT=$(printf '%s\n' "$SSH_CONFIG_EFETIVA" | awk '$1 == "permitrootlogin" {print $2; exit}')
    case "$SSH_ROOT" in
      yes) linha 'PermitRootLogin efetivo: yes — login SSH de root permitido (conforme as demais regras de autenticação).' ;;
      prohibit-password|without-password) linha "PermitRootLogin efetivo: $SSH_ROOT — login SSH de root permitido sem senha, sujeito às demais regras de autenticação." ;;
      forced-commands-only) linha 'PermitRootLogin efetivo: forced-commands-only — root permitido apenas com chave que imponha comando forçado.' ;;
      no) linha 'PermitRootLogin efetivo: no — login SSH de root proibido.' ;;
      *) linha 'Não foi possível localizar PermitRootLogin na configuração efetiva do sshd.' ;;
    esac
    linha 'A configuração efetiva foi avaliada para user=root, host=localhost, addr=127.0.0.1; regras Match dependentes do cliente podem variar.'
  else
    linha 'Não foi possível avaliar a configuração efetiva via sshd -T (verifique privilégios e validade da configuração).'
  fi
elif [ -r /etc/ssh/sshd_config ]; then
  ROOT_CFG=$(awk 'tolower($1)=="permitrootlogin" {v=$2} END {if(v!="") print v}' /etc/ssh/sshd_config)
  linha "sshd não está disponível para avaliar Includes, Match e padrões; diretiva literal no arquivo principal: ${ROOT_CFG:-não definida}."
else linha 'sshd e configuração SSH não encontrados.'; fi
linha ''
USUARIO_CHAVES="${SUDO_USER:-$(id -un 2>/dev/null || printf 'desconhecido')}"
HOME_CHAVES=''
if [ -n "$USUARIO_CHAVES" ] && comando_disponivel getent; then
  HOME_CHAVES=$(getent passwd "$USUARIO_CHAVES" | awk -F: -v usuario="$USUARIO_CHAVES" '$1 == usuario {print $6; exit}')
elif [ -n "$USUARIO_CHAVES" ] && [ -r /etc/passwd ]; then
  HOME_CHAVES=$(awk -F: -v usuario="$USUARIO_CHAVES" '$1 == usuario {print $6; exit}' /etc/passwd)
fi
if [ -z "${SUDO_USER:-}" ] && [ -z "$HOME_CHAVES" ]; then HOME_CHAVES="${HOME:-}"; fi
linha "--- Chaves SSH autorizadas de $USUARIO_CHAVES (SUDO_USER quando executado via sudo) ---"
if [ -n "$HOME_CHAVES" ] && [ -r "$HOME_CHAVES/.ssh/authorized_keys" ]; then
  # Exibe fingerprints em vez do conteúdo das chaves, reduzindo exposição de dados.
  if comando_disponivel ssh-keygen; then
    ssh-keygen -lf "$HOME_CHAVES/.ssh/authorized_keys" >> "$ARQUIVO" 2>&1 || linha '[Não foi possível calcular fingerprints.]'
  else
    awk 'NF && $1 !~ /^#/ {print "Tipo de chave: " $1 " (fingerprint indisponível sem ssh-keygen)"}' "$HOME_CHAVES/.ssh/authorized_keys" >> "$ARQUIVO"
  fi
else linha 'Nenhum arquivo authorized_keys legível encontrado para o usuário indicado.'; fi

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
  coletar_falhas_auth 'journal do sistema' journalctl --since '7 days ago' --no-pager
elif [ -r /var/log/auth.log ]; then
  coletar_falhas_auth '/var/log/auth.log' cat /var/log/auth.log
elif [ -r /var/log/secure ]; then
  coletar_falhas_auth '/var/log/secure' cat /var/log/secure
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

# Tenta os transportes disponíveis; sucesso indica aceitação pelo transporte, não entrega final.
if [ -n "${AUDIT_EMAIL:-}" ]; then
  EMAIL_ACEITO=0
  EMAIL_TRANSPORTE_ENCONTRADO=0
  if comando_disponivel msmtp; then
    EMAIL_TRANSPORTE_ENCONTRADO=1
    if {
      printf 'To: %s\n' "$AUDIT_EMAIL"
      printf 'Subject: Auditoria do servidor %s\n' "$(hostname 2>/dev/null)"
      printf 'MIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\n\n'
      cat "$ARQUIVO"
    } | msmtp "$AUDIT_EMAIL"; then
      EMAIL_ACEITO=1
      printf "${VERDE}[+] Relatório aceito para envio pelo msmtp para %s; a entrega final depende do servidor SMTP.${RESET}\n" "$AUDIT_EMAIL"
    else printf "${AMARELO}[!] msmtp foi encontrado, mas não conseguiu enviar; tentando outro transporte disponível.${RESET}\n"; fi
  fi
  if [ "$EMAIL_ACEITO" -eq 0 ] && comando_disponivel sendmail; then
    EMAIL_TRANSPORTE_ENCONTRADO=1
    if {
      printf 'To: %s\n' "$AUDIT_EMAIL"
      printf 'Subject: Auditoria do servidor %s\n' "$(hostname 2>/dev/null)"
      printf 'MIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\n\n'
      cat "$ARQUIVO"
    } | sendmail -t; then
      EMAIL_ACEITO=1
      printf "${VERDE}[+] Relatório aceito pelo sendmail para processamento; a entrega final não foi confirmada.${RESET}\n"
    else printf "${AMARELO}[!] sendmail foi encontrado, mas não aceitou o relatório; tentando mail se disponível.${RESET}\n"; fi
  fi
  if [ "$EMAIL_ACEITO" -eq 0 ] && comando_disponivel mail; then
    EMAIL_TRANSPORTE_ENCONTRADO=1
    if mail -s "Auditoria do servidor $(hostname 2>/dev/null)" "$AUDIT_EMAIL" < "$ARQUIVO"; then
      EMAIL_ACEITO=1
      printf "${VERDE}[+] mail aceitou o relatório via transporte configurado; a entrega final não foi confirmada.${RESET}\n"
    else printf "${AMARELO}[!] mail está instalado, mas não confirmou transporte funcional.${RESET}\n"; fi
  fi
  if [ "$EMAIL_ACEITO" -eq 0 ]; then
    if [ "$EMAIL_TRANSPORTE_ENCONTRADO" -eq 0 ]; then
      printf "${AMARELO}[!] Relatório gerado, mas não enviado: msmtp, sendmail e mail não estão disponíveis. Arquivo: %s${RESET}\n" "$ARQUIVO"
    else
      printf "${AMARELO}[!] Relatório gerado, mas não enviado: nenhum transporte disponível aceitou o envio. Arquivo: %s${RESET}\n" "$ARQUIVO"
    fi
  fi
fi
