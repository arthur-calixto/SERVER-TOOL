#!/bin/bash
# Script de ferramentas uteis
########################################################
# Desenvolvido por Arthur Calixto
# Ultima atualizacao: 25/02/2026
# Objetivo: Automatizar tarefas
########################################################

# Variaveis
v_ip=$(ip addr show | grep "inet " | grep -v 127.0.0. | head -1 | cut -d" " -f6 | cut -d/ -f1)
dir_stack="/repositorio/arthur/JSTACK"

# Funcao de cabecalho
function cabecalho() {
    clear
    echo " ###################################################################################################"
    echo " ########             SERVER-TOOL AUTOMAÇÕES DE TAREFAS       $v_ip         v 2.0 ########"
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

    echo "Lendo JAVA_HOME do standalone.sh..."
    
    # Procurar pela linha que define JAVA_HOME com caminho absoluto (começa com /)
    # Ignora linhas comentadas e linhas com comandos como cygpath
    java_home_linha=$(grep "JAVA_HOME=" "$standalone_sh" | grep -v "^#" | grep -v "^\s*#" | grep -v "cygpath" | grep -v '`' | grep -v '\$(' | head -1)
    
    if [[ -z "$java_home_linha" ]]; then
        echo "⚠ JAVA_HOME não encontrado no standalone.sh"
        jdk_encontrado=$(ls -d "$base"/jdk* 2>/dev/null | head -1)
        if [[ -n "$jdk_encontrado" ]]; then
            java_home_extraido="$jdk_encontrado"
        else
            read -p "Digite o caminho do JAVA_HOME: " java_home_extraido
        fi
    else
        # Extrair apenas o valor entre JAVA_HOME= e ; (ou fim da linha)
        java_home_extraido=$(echo "$java_home_linha" | sed 's/.*JAVA_HOME=//; s/;.*//' | tr -d '"' | tr -d "'" | xargs)
        
        echo "Extraído do standalone.sh: $java_home_extraido"
    fi

    # Validar se o JAVA_HOME existe
    if [[ ! -d "$java_home_extraido" ]]; then
        echo "❌ JAVA_HOME não existe: $java_home_extraido"
        
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
# Função para listar monitoramentos JSTACK existentes
###############################################################
function listar_jstacks() {
    local base_path="$1"
    
    echo "Procurando monitoramentos JSTACK existentes..."
    echo ""
    
    # Listar diretórios que começam com jstack_
    jstackDirs=($(ls -d "$base_path"/jstack_* 2>/dev/null))
    
    if [[ ${#jstackDirs[@]} -eq 0 ]]; then
        echo "❌ Nenhum monitoramento JSTACK encontrado em $base_path"
        return 1
    fi
    
    echo "Monitoramentos encontrados:"
    for dir in "${jstackDirs[@]}"; do
        echo "  • $(basename "$dir")"
    done
    echo ""
    
    return 0
}

###############################################################
# Função para selecionar qual JSTACK remover
###############################################################
function selecionar_jstack_remover() {
    local base_path="$1"
    
    # Listar diretórios que começam com jstack_
    jstackDirs=($(ls -d "$base_path"/jstack_* 2>/dev/null))
    
    if [[ ${#jstackDirs[@]} -eq 0 ]]; then
        return 1
    fi
    
    PS3='Selecione o monitoramento a remover: '
    select jstack_selected in "${jstackDirs[@]}" "CANCELAR"; do
        if [[ "$jstack_selected" == "CANCELAR" ]]; then
            echo "Operação cancelada"
            return 1
        elif [[ -n "$jstack_selected" ]]; then
            jstack_path="$jstack_selected"
            jstack_name=$(basename "$jstack_path")
            echo "✔ Selecionado: $jstack_name"
            break
        fi
    done
    echo ""
}

###############################################################
# Função para remover monitoramento JSTACK
###############################################################
function opcao_remover_jstack() {
    cabecalho
    echo "Removendo monitoramento JSTACK para: $v_home_dest"
    echo ""
    
    base="/home/$v_home_dest"
    
    # Listar monitoramentos existentes
    listar_jstacks "$base"
    if [[ $? -ne 0 ]]; then
        read -p "Pressione ENTER para continuar..."
        return 1
    fi
    
    # Selecionar qual remover
    selecionar_jstack_remover "$base"
    if [[ -z "$jstack_path" ]]; then
        read -p "Pressione ENTER para continuar..."
        return 1
    fi
    
    # Confirmação
    echo ""
    echo -e "\e[33m⚠ ATENÇÃO: Esta ação é irreversível!\e[0m"
    echo ""
    echo "Será removido:"
    echo "  • Diretório: $jstack_path"
    echo "  • Todos os logs dentro do diretório"
    echo "  • Entrada no crontab associada"
    echo ""
    read -p "Deseja realmente remover? (s/N): " confirmacao
    
    if [[ "$confirmacao" != "s" && "$confirmacao" != "S" ]]; then
        echo "Operação cancelada"
        read -p "Pressione ENTER para continuar..."
        return 1
    fi
    
    echo ""
    echo "Removendo monitoramento..."
    
    # Remover entrada do crontab
    echo "• Removendo do crontab..."
    crontab -l 2>/dev/null | grep -v "$jstack_path/gerar_log.sh" | crontab -
    if [[ $? -eq 0 ]]; then
        echo "  ✔ Entrada do crontab removida"
    else
        echo "  ⚠ Erro ao remover do crontab (pode não existir)"
    fi
    
    # Remover diretório
    echo "• Removendo diretório e arquivos..."
    rm -rf "$jstack_path"
    if [[ $? -eq 0 ]]; then
        echo "  ✔ Diretório removido: $jstack_path"
    else
        echo "  ❌ Erro ao remover diretório"
        read -p "Pressione ENTER para continuar..."
        return 1
    fi
    
    echo ""
    echo -e "\e[32m╔═══════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[32m║        ✓ MONITORAMENTO REMOVIDO COM SUCESSO!             ║\e[0m"
    echo -e "\e[32m╚═══════════════════════════════════════════════════════════╝\e[0m"
    echo ""
    echo "Cliente:     $v_home_dest"
    echo "Removido:    $jstack_name"
    echo "Diretório:   $jstack_path"
    echo ""
    read -p "Pressione ENTER para continuar..."
}

###############################################################
# Menu de Monitoramento JSTACK
###############################################################
function menu_jstack() {
    cabecalho
    echo "MONITORAMENTO JSTACK"
    echo "===================="
    echo "1) Adicionar monitoramento"
    echo "2) Remover monitoramento"
    echo "3) Voltar ao menu principal"
    echo ""
    read -p "Escolha uma opção: " opcao_jstack

    case $opcao_jstack in
        1)
            userhome
            opcao_jstack
            menu_jstack
            ;;
        2)
            userhome
            opcao_remover_jstack
            menu_jstack
            ;;
        3)
            menu_principal
            ;;
        *)
            echo "❌ Opção inválida!"
            sleep 2
            menu_jstack
            ;;
    esac
}

###############################################################
# Função Monitoramento Flight Recorder (JFR)
###############################################################
function opcao_flight_recorder() {

    cabecalho
    echo "MONITORAMENTO FLIGHT RECORDER (JFR)"
    echo "===================================="
    echo ""

    base="/home/$v_home_dest"

    # Selecionar Wildfly (igual JSTACK)
    selecionar_wildfly "$base"
    if [[ -z "$wildfly_name" ]]; then
        echo "❌ Nenhum Wildfly selecionado"
        read -p "Pressione ENTER para continuar..."
        return 1
    fi

    # Extrair JAVA_HOME
    extrair_java_home "$wildfly_path"
    if [[ -z "$java_home_extraido" ]]; then
        echo "❌ JAVA_HOME não configurado"
        read -p "Pressione ENTER para continuar..."
        return 1
    fi

    # Perguntar duração
    echo ""
    read -p "Informe o tempo de monitoramento (em segundos): " tempo_monitoramento

    if ! [[ "$tempo_monitoramento" =~ ^[0-9]+$ ]]; then
        echo "❌ Tempo inválido!"
        read -p "Pressione ENTER para continuar..."
        return 1
    fi

    echo ""
    echo "Procurando PID do Wildfly..."

    processoWF=$(ps ax | grep "$wildfly_name" | grep java | grep -v grep | awk '{print $1}' | head -1)

    if [[ -z "$processoWF" ]]; then
        echo "❌ Processo do Wildfly não encontrado!"
        read -p "Pressione ENTER para continuar..."
        return 1
    fi

    echo "✔ PID encontrado: $processoWF"
    echo ""

    # Nome com data e hora
    data_atual=$(date +%d%m%Y-%H%M)
    nome_arquivo="myrecording${data_atual}.jfr"

    echo "Iniciando gravação JFR..."
    echo ""

    "$java_home_extraido/bin/jcmd" "$processoWF" JFR.start duration=${tempo_monitoramento}s filename="$base/$nome_arquivo"

    echo ""
    echo -e "\e[32m╔═══════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[32m║        ✓ FLIGHT RECORDER INICIADO COM SUCESSO!           ║\e[0m"
    echo -e "\e[32m╚═══════════════════════════════════════════════════════════╝\e[0m"
    echo ""
    echo "Cliente:    $v_home_dest"
    echo "Wildfly:    $wildfly_name"
    echo "PID:        $processoWF"
    echo "Duração:    ${tempo_monitoramento}s"
    echo "Arquivo:    $base/$nome_arquivo"
    echo ""

    read -p "Pressione ENTER para continuar..."
}


###############################################################
# Menu Flight Recorder
###############################################################
function menu_flight_recorder() {

    cabecalho
    echo "MONITORAMENTO FLIGHT RECORDER"
    echo "============================="
    echo "1) Iniciar gravação"
    echo "2) Voltar ao menu principal"
    echo ""

    read -p "Escolha uma opção: " opcao_fr

    case $opcao_fr in
        1)
            userhome
            opcao_flight_recorder
            menu_flight_recorder
            ;;
        2)
            menu_principal
            ;;
        *)
            echo "❌ Opção inválida!"
            sleep 2
            menu_flight_recorder
            ;;
    esac
}

###############################################################
# Menu principal
###############################################################
function menu_principal() {
    cabecalho
    echo "MENU PRINCIPAL"
    echo "=============="
    echo "1) Monitoramento JSTACK"
    echo "2) Monitoramento FLIGHT RECORDER"
    echo "3) Sair"
    echo ""
    read -p "Escolha uma opção: " opcao

    case $opcao in
        1)
            menu_jstack
            ;;
        2)
            menu_flight_recorder
            ;;    
        3)
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