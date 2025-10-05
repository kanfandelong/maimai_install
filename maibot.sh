#!/bin/bash

# =============================================================================
# 配置部分
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_CONFIG_FILE="$SCRIPT_DIR/path.conf"


# 颜色定义
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
MAGENTA='\033[35m'
CURRENT_USER=$(whoami)

# =============================================================================
# 日志函数
# =============================================================================
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error() { echo -e "${RED}[ERROR]${RESET} $1"; }

print_line() {
    echo -e "${CYAN}========================================================${RESET}"
}

print_title() {
    echo ""
    print_line
    echo -e "${BOLD}${MAGENTA}$1${RESET}"
    print_line
}

# =============================================================================
# 路径初始化
# =============================================================================
init_paths() {
    # 如果有 path.conf 文件,直接读取
    if [ -f "$PATH_CONFIG_FILE" ]; then
        DEPLOY_BASE=$(cat "$PATH_CONFIG_FILE" | tr -d '\n\r' | xargs)
        info "从配置文件加载路径: $DEPLOY_BASE"
    # 否则检测同级目录
    elif [ -d "$SCRIPT_DIR/MaiBot" ] && [ -d "$SCRIPT_DIR/MaiBot-Napcat-Adapter" ]; then
        DEPLOY_BASE="$SCRIPT_DIR"
        info "使用同级目录: $DEPLOY_BASE"
    else
        error "未找到 MaiBot 目录,请使用 --init 参数配置路径"
        echo "用法: $0 --init=/path/to/parent/dir"
        exit 1
    fi
    
    DEPLOY_DIR="$DEPLOY_BASE/MaiBot"
    ADAPTER_DIR="$DEPLOY_BASE/MaiBot-Napcat-Adapter"
    DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"
}

# =============================================================================
# 工具函数
# =============================================================================
session_exists() {
    screen -ls | grep -q "\.$1[[:space:]]"
    return $?
}


check_service_status() {
    local service=$1
    if session_exists "$service"; then
        echo -e "${GREEN}[运行中]${RESET}"
        return 0
    else
        echo -e "${RED}[已停止]${RESET}"
        return 1
    fi
}

press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
}

# =============================================================================
# 函数
# =============================================================================
start_maibot() {
    info "正在启动 MaiBot..."
    
    if session_exists "MaiBot"; then
        warn "MaiBot 已在运行中"
        return 1
    fi
    screen -dmS MaiBot bash -c "cd \"$DEPLOY_DIR\" && source .venv/bin/activate && python3 bot.py"
    
    sleep 2
    
    if session_exists "MaiBot"; then
        success "MaiBot 启动成功"
        return 0
    else
        error "MaiBot 启动失败,请检查日志"
        return 1
    fi
}

start_adapter() {
    info "正在启动 MaiBot-Napcat-Adapter..."
    
    if session_exists "MaiBot-Napcat-Adapter"; then
        warn "MaiBot-Napcat-Adapter 已在运行中"
        return 1
    fi
    
    cd "$ADAPTER_DIR" || { error "无法进入目录 $ADAPTER_DIR"; return 1; }
    
    screen -dmS MaiBot-Napcat-Adapter bash -c "cd '$ADAPTER_DIR' && source $DEPLOY_DIR/.venv/bin/activate && python3 main.py"

    
    sleep 2
    
    if session_exists "MaiBot-Napcat-Adapter"; then
        success "MaiBot-Napcat-Adapter 启动成功"
        return 0
    else
        error "MaiBot-Napcat-Adapter 启动失败,请检查日志"
        return 1
    fi
}

stop_maibot() {
    info "正在停止 MaiBot..."
    
    if ! session_exists "MaiBot"; then
        warn "MaiBot 未运行"
        return 1
    fi
    
    screen -S MaiBot -X quit
    sleep 1
    
    if ! session_exists "MaiBot"; then
        success "MaiBot 已停止"
        return 0
    else
        error "MaiBot 停止失败"
        return 1
    fi
}

stop_adapter() {
    info "正在停止 MaiBot-Napcat-Adapter..."
    
    if ! session_exists "MaiBot-Napcat-Adapter"; then
        warn "MaiBot-Napcat-Adapter 未运行"
        return 1
    fi
    
    screen -S MaiBot-Napcat-Adapter -X quit 
    sleep 1
    
    if ! session_exists "MaiBot-Napcat-Adapter"; then
        success "MaiBot-Napcat-Adapter 已停止"
        return 0
    else
        error "MaiBot-Napcat-Adapter 停止失败"
        return 1
    fi
}

start_all() {
    print_title "启动所有服务"
    
    start_maibot
    local maibot_result=$?
    
    start_adapter
    local adapter_result=$?
    
    echo ""
    if [ $maibot_result -eq 0 ] && [ $adapter_result -eq 0 ]; then
        success "所有服务启动完成"
    else
        warn "部分服务启动失败,请检查日志"
    fi
    
    press_any_key
}

stop_all() {
    print_title "停止所有服务"
    
    stop_maibot
    stop_adapter
    
    echo ""
    success "所有服务已停止"
    
    press_any_key
}

attach_session() {
    local session=$1
    local name=$2
    
    if ! session_exists "$session"; then
        error "$name 未运行,无法附加"
        press_any_key
        return 1
    fi
    
    info "正在附加到 $name 会话..."
    info "使用 Ctrl+A 然后按 D 来分离会话"
    sleep 2
    screen -r "$session"
}

# =============================================================================
# 菜单显示
# =============================================================================
show_menu() {
    clear
    print_title "MaiBot  2025.10.03"
    
    echo -e "${CYAN}系统信息:${RESET}"
    echo -e "  用户: ${GREEN}$CURRENT_USER${RESET}"
    echo -e "  时间: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "  路径: ${GREEN}$DEPLOY_BASE${RESET}"
    echo ""
    
    echo -e "${CYAN}服务状态:${RESET}"
    echo -e "  MaiBot:                 $(check_service_status 'MaiBot')"
    echo -e "  MaiBot-Napcat-Adapter:  $(check_service_status 'MaiBot-Napcat-Adapter')"
    echo ""
    
    print_line
    echo -e "${BOLD}${YELLOW}操作菜单:${RESET}"
    print_line
    
    echo -e "  ${BOLD}${GREEN}[1]${RESET} 启动所有服务 (MaiBot + Adapter)"
    echo -e "  ${BOLD}${GREEN}[2]${RESET} 停止所有服务"
    echo ""
    echo -e "  ${BOLD}${GREEN}[3]${RESET} 仅停止 MaiBot"
    echo -e "  ${BOLD}${GREEN}[4]${RESET} 仅停止 MaiBot-Napcat-Adapter"
    echo ""
    echo -e "  ${BOLD}${GREEN}[5]${RESET} 附加到 MaiBot 会话"
    echo -e "  ${BOLD}${GREEN}[6]${RESET} 附加到 MaiBot-Napcat-Adapter 会话"
    echo ""
    echo -e "  ${BOLD}${GREEN}[7]${RESET} 前台启动 MaiBot "
    echo -e "  ${BOLD}${GREEN}[8]${RESET} 前台启动 MaiBot-Napcat-Adapter "
    echo ""
    echo -e "  ${BOLD}${GREEN}[0]${RESET} 退出脚本"
    
    print_line
    echo ""
    echo -ne "${BOLD}${YELLOW}请选择操作 [0-8]: ${RESET}"
}

# =============================================================================
# 主程序
# =============================================================================
main() {
    # 处理 --init 参数
    if [[ $1 == --init=* ]]; then
        local init_path="${1#*=}"
        
        # 处理相对路径
        if [[ ! "$init_path" = /* ]]; then
            init_path="$(cd "$init_path" 2>/dev/null && pwd)"
            if [ $? -ne 0 ]; then
                error "路径不存在: ${1#*=}"
                exit 1
            fi
        fi
        
        # 验证路径
        if [ ! -d "$init_path/MaiBot" ]; then
            error "未找到 MaiBot 目录: $init_path/MaiBot"
            exit 1
        fi
        
        if [ ! -d "$init_path/MaiBot-Napcat-Adapter" ]; then
            error "未找到 MaiBot-Napcat-Adapter 目录: $init_path/MaiBot-Napcat-Adapter"
            exit 1
        fi
        
        # 写入配置文件
        echo "$init_path" > "$PATH_CONFIG_FILE"
        success "路径配置成功: $init_path"
        success "配置文件: $PATH_CONFIG_FILE"
        exit 0
    fi
    
    # 初始化路径
    init_paths
    
    # 主循环
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) start_all ;;
            2) stop_all ;;
            3) 
                print_title "停止 MaiBot"
                stop_maibot
                press_any_key
                ;;
            4) 
                print_title "停止 MaiBot-Napcat-Adapter"
                stop_adapter
                press_any_key
                ;;
            5) attach_session "MaiBot" "MaiBot" ;;
            6) attach_session "MaiBot-Napcat-Adapter" "MaiBot-Napcat-Adapter" ;;
            7) 
                print_title "前台启动 MaiBot"
                # 如果已运行先停止
                if session_exists "MaiBot"; then
                    stop_maibot
                fi
                cd "$DEPLOY_DIR" || { error "无法进入目录 $DEPLOY_DIR"; press_any_key; continue; }
                echo -e "${GREEN}前台启动 MaiBot,使用 Ctrl+C 停止${RESET}"
                uv run bot.py
                press_any_key
                ;;
            8) 
                print_title "前台启动 MaiBot-Napcat-Adapter"
                # 如果已运行先停止
                if session_exists "MaiBot-Napcat-Adapter"; then
                    stop_adapter
                fi
                cd "$ADAPTER_DIR" || { error "无法进入目录 $ADAPTER_DIR"; press_any_key; continue; }
                source "$ADAPTER_DIR/.MaiBot-Napcat-Adapter/bin/activate"
                echo -e "${GREEN}前台启动 MaiBot-Napcat-Adapter,使用 Ctrl+C 停止${RESET}"
                uv run main.py
                press_any_key
                ;;
            114514) echo "原始脚本仓库https://github.com/Astriora/Antlia 本脚本仓库地址https://github.com/kanfandelong/maimai_install" && press_any_key  ;;
            0)
                exit 0
                ;;
            *)
                error "无效选项,请重新选择"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main "$@"