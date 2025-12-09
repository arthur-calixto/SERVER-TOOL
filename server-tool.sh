#!/bin/bash
# Script de ferramentas uteis
########################################################
# Desenvolvido por Arthur Calixto
# Ultima atualizacao: 08/12/2025
# Objetivo: Automatizar tarefas
########################################################

# Variaveis
v_ip=$(ip addr show | grep "inet " | grep -v 127.0.0. | head -1 | cut -d" " -f6 | cut -d/ -f1)
dir_stack="/repositorio/arthur/JSTACK"

# Funcao de cabecalho
function cabecalho() {
    clear
    echo " ###################################################################################################"
    echo " ########             SERVER-TOOL AUTOMAÇÕES DE TAREFAS       $v_ip         v 1.0 ########"
    echo " ###################################################################################################"
    echo " "
}

# Função achar clientes no /home
function userhome() {
    cabecalho
    PS3='
========================================================================
Número do cliente a ser atualizado: '
    select v_home_dest in $(ls /home/ | grep -v found | grep -v FMC 2>> /dev/null) "OUTRAS"; do
        break
    done

    cabecalho

    # Validação se o usuário selecionou uma opção válida
    if [[ -z "$v_home_dest" ]]; then
        echo "❌ Nenhum cliente selecionado!"
        exit 1
    fi

    if [[ "$v_home_dest" == "OUTRAS" ]]; then
        echo "Opção OUTRAS selecionada"
        read -p "Digite o caminho completo: " v_home_dest
    fi

    # Validação se o diretório existe
    if [[ ! -d "/home/$v_home_dest" ]]; then
        echo "❌ Diretório /home/$v_home_dest não existe!"
        exit 1
    fi

    cd "/home/$v_home_dest" || exit 1
    local2="/home/$v_home_dest"
    pwd
    echo ""
}

###############################################################
# Função para selecionar Wildfly
###############################################################
function selecionar_wildfly() {
    local base_path="$1"

    echo "Procurando instâncias do Wildfly..."

    # Listar diretórios que começam com Wildfly_
    wildflyDirs=($(ls -d "$base_path"/Wildfly_* 2>/dev/null))

    if [[ ${#wildflyDirs[@]} -eq 0 ]]; then
        echo "❌ Nenhuma instância do Wildfly encontrada"
        return 1
    fi

    PS3='Selecione o Wildfly: '
    select wildfly_path in "${wildflyDirs[@]}"; do
        if [[ -n "$wildfly_path" ]]; then
            wildfly_name=$(basename "$wildfly_path")
            echo "✔ Selecionado: $wildfly_name"
            break
        fi
    done
    echo ""
}

###############################################################
# Função para extrair JAVA_HOME do standalone.sh
###############################################################
function extrair_java_home() {
    local wildfly_path="$1"
    local standalone_sh="$wildfly_path/bin/standalone.sh"

    if [[ ! -f "$standalone_sh" ]]; then
        echo "⚠ standalone.sh não encontrado"
        return 1
    fi

    # Procurar por JAVA_HOME no arquivo standalone.sh
    java_home_linha=$(grep -E "^JAVA_HOME=|^export JAVA_HOME=" "$standalone_sh" | tail -1)
    java_home_extraido=$(echo "$java_home_linha" | cut -d'=' -f2 | tr -d ';' | tr -d '"' | tr -d "'" | xargs)

    if [[ -z "$java_home_extraido" ]]; then
        # Procurar diretórios JDK
        jdk_encontrado=$(ls -d "$base"/jdk* 2>/dev/null | head -1)

        if [[ -n "$jdk_encontrado" ]]; then
            java_home_extraido="$jdk_encontrado"
        else
            read -p "Digite o caminho do JAVA_HOME: " java_home_extraido
        fi
    else
        # Resolver variáveis como $USER, $HOME, etc
        java_home_extraido="${java_home_extraido//\$USER/$v_home_dest}"
        java_home_extraido="${java_home_extraido//\$\{USER\}/$v_home_dest}"
        java_home_extraido="${java_home_extraido//\$HOME/\/home\/$v_home_dest}"
        java_home_extraido="${java_home_extraido//\$\{HOME\}/\/home\/$v_home_dest}"
        java_home_extraido="${java_home_extraido//\~\//\/home\/$v_home_dest\/}"
        java_home_extraido=$(eval echo "$java_home_extraido")
    fi

    # Validar se o JAVA_HOME existe
    if [[ ! -d "$java_home_extraido" ]]; then
        jdk_encontrado=$(ls -d "$base"/jdk* 2>/dev/null | head -1)

        if [[ -n "$jdk_encontrado" ]]; then
            read -p "JAVA_HOME não existe. Usar $jdk_encontrado? (s/n): " usar_alternativo
            if [[ "$usar_alternativo" == "s" || "$usar_alternativo" == "S" ]]; then
                java_home_extraido="$jdk_encontrado"
            else
                read -p "Digite o caminho correto: " java_home_extraido
            fi
        else
            read -p "Digite o caminho correto: " java_home_extraido
        fi
    fi

    echo "✔ JAVA_HOME: $java_home_extraido"
    echo ""
}

###############################################################
# Função para editar o stack.sh
###############################################################
function editar_stack_sh() {
    local arquivo_stack="$1"
    local cliente="$2"
    local wildfly_nome="$3"
    local java_home_path="$4"
    local pasta_jstack="$5"
    local pasta_log="$6"

    if [[ ! -f "$arquivo_stack" ]]; then
        echo "❌ stack.sh não encontrado"
        return 1
    fi

    # Substituir os valores no arquivo
    sed -i "s|source /home/.*/\.bash_profile|source /home/$cliente/.bash_profile|g" "$arquivo_stack"
    sed -i "s|export JAVA_HOME=.*|export JAVA_HOME=\"$java_home_path\"|g" "$arquivo_stack"
    sed -i "s|JAVA_HOME=.*; export JAVA_HOME|JAVA_HOME=$java_home_path; export JAVA_HOME|g" "$arquivo_stack"
    sed -i "s|export STACK_HOME=.*|export STACK_HOME=\"$pasta_jstack\"|g" "$arquivo_stack"
    sed -i "s|export LOG_HOME=.*|export LOG_HOME=\"$pasta_log\"|g" "$arquivo_stack"
    sed -i "s|export comandoJStack=.*|export comandoJStack=\"\$JAVA_HOME/bin/jstack\"|g" "$arquivo_stack"

    # Substituir o processoWF com o wildfly correto
    sed -i "s|grep Wildfly_[0-9]*|grep $wildfly_nome|g" "$arquivo_stack"
    sed -i "s|export processoWF=.*|export processoWF=\$(ps ax \| grep $wildfly_nome \| grep java \| awk '{print \$1}')|g" "$arquivo_stack"

    echo "✔ stack.sh configurado"
}

###############################################################
# Função para editar o gerar_log.sh
###############################################################
function editar_gerar_log_sh() {
    local arquivo_gerar="$1"
    local pasta_jstack_path="$2"

    if [[ ! -f "$arquivo_gerar" ]]; then
        echo "❌ gerar_log.sh não encontrado"
        return 1
    fi

    # Substituir qualquer caminho antigo pelo novo caminho completo
    sed -i "s|/home/.*/jstack.*/\./stack\.sh.*|$pasta_jstack_path/stack.sh log|g" "$arquivo_gerar"
    sed -i "s|/home/.*/jstack.*/stack\.sh.*|$pasta_jstack_path/stack.sh log|g" "$arquivo_gerar"
    sed -i "s|/home/.*/stacks/\./stack\.sh.*|$pasta_jstack_path/stack.sh log|g" "$arquivo_gerar"
    sed -i "s|/home/.*/stacks/stack\.sh.*|$pasta_jstack_path/stack.sh log|g" "$arquivo_gerar"

    # Garantir que não tenha ./ no caminho
    sed -i "s|\./stack\.sh|$pasta_jstack_path/stack.sh|g" "$arquivo_gerar"

    # Garantir que o parâmetro 'log' esteja presente
    sed -i "s|stack\.sh$|stack.sh log|g" "$arquivo_gerar"

    echo "✔ gerar_log.sh configurado"
}

###############################################################
# Função para preparar a estrutura de monitoramento JSTACK
###############################################################
function opcao_jstack() {
    cabecalho
    echo "Configurando monitoramento JSTACK para: $v_home_dest"
    echo ""

    base="/home/$v_home_dest"

    # Selecionar Wildfly ANTES de criar as pastas
    selecionar_wildfly "$base"
    if [[ -z "$wildfly_name" ]]; then
        echo "❌ Nenhum Wildfly selecionado"
        return 1
    fi

    # Criar pastas com o nome do Wildfly
    pasta_jstack="$base/jstack_$wildfly_name"
    pasta_log="$pasta_jstack/log"

    mkdir -p "$pasta_jstack" "$pasta_log"

    # Extrair JAVA_HOME
    extrair_java_home "$wildfly_path"
    if [[ -z "$java_home_extraido" ]]; then
        echo "❌ JAVA_HOME não configurado"
        return 1
    fi

    # Verificar diretório de origem dos scripts
    if [[ ! -d "$dir_stack" ]]; then
        echo "❌ Diretório $dir_stack não existe"
        read -p "Digite o caminho correto: " dir_stack_novo

        if [[ -d "$dir_stack_novo" ]]; then
            dir_stack="$dir_stack_novo"
        else
            encontrado=$(find /repositorio /home -name "gerar_log.sh" 2>/dev/null | head -1)
            if [[ -n "$encontrado" ]]; then
                dir_stack=$(dirname "$encontrado")
                echo "✔ Encontrado em: $dir_stack"
            else
                echo "❌ Arquivos não localizados"
                return 1
            fi
        fi
    fi

    # Copiar scripts
    echo "Copiando scripts..."
    if [[ -f "$dir_stack/gerar_log.sh" ]]; then
        cp "$dir_stack/gerar_log.sh" "$pasta_jstack/" && echo "✔ gerar_log.sh copiado"
    else
        echo "❌ gerar_log.sh não encontrado"
    fi

    if [[ -f "$dir_stack/stack.sh" ]]; then
        cp "$dir_stack/stack.sh" "$pasta_jstack/" && echo "✔ stack.sh copiado"
    else
        echo "❌ stack.sh não encontrado"
        return 1
    fi

    # Permissões
    chmod +x "$pasta_jstack/gerar_log.sh" "$pasta_jstack/stack.sh" 2>/dev/null

    echo ""

    # Editar scripts (passando as variáveis corretas)
    editar_stack_sh "$pasta_jstack/stack.sh" "$v_home_dest" "$wildfly_name" "$java_home_extraido" "$pasta_jstack" "$pasta_log"
    editar_gerar_log_sh "$pasta_jstack/gerar_log.sh" "$pasta_jstack"

    echo ""
    echo "Configurando crontab..."
    cron_entry="*/1 8-19 * * * $pasta_jstack/gerar_log.sh >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "$pasta_jstack/gerar_log.sh"; echo "$cron_entry") | crontab -
    echo "✔ Crontab configurado"

    echo ""
    echo -e "\e[32m╔═══════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[32m║        ✓ MONITORAMENTO CONFIGURADO COM SUCESSO!          ║\e[0m"
    echo -e "\e[32m╚═══════════════════════════════════════════════════════════╝\e[0m"
    echo ""
    echo "Cliente:   $v_home_dest"
    echo "Wildfly:   $wildfly_name"
    echo "JAVA_HOME: $java_home_extraido"
    echo "Diretório: $pasta_jstack"
    echo "Execução:  A cada minuto das 08h às 19h"
    echo ""
    read -p "Pressione ENTER para continuar..."
}

###############################################################
# Menu principal
###############################################################
function menu_principal() {
    cabecalho
    echo "MENU PRINCIPAL"
    echo "=============="
    echo "1) Configurar monitoramento JSTACK"
    echo "2) Sair"
    echo ""
    read -p "Escolha uma opção: " opcao

    case $opcao in
        1)
            userhome
            opcao_jstack
            menu_principal
            ;;
        2)
            echo "Saindo..."
            exit 0
            ;;
        *)
            echo "❌ Opção inválida!"
            sleep 2
            menu_principal
            ;;
    esac
}

###############################################################
# Fluxo principal
###############################################################

menu_principal