#!/bin/bash

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
    PLUGIN_DIR="$DEPLOY_DIR/plugins"
    ADAPTER_DIR="$DEPLOY_BASE/MaiBot-Napcat-Adapter"
    if [ -d "$ADAPTER_DIR/.venv" ]; then
        ADAPTER_venv=$ADAPTER_DIR/.venv
    else
        ADAPTER_venv=$DEPLOY_DIR/.venv
    fi
    DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"

    # PID 文件路径
    MAIBOT_PID_FILE="$DEPLOY_DIR/maibot.pid"
    ADAPTER_PID_FILE="$ADAPTER_DIR/adapter.pid"

    # 日志文件路径
    MAIBOT_LOG_FILE="$DEPLOY_DIR/maibot.log"
    ADAPTER_LOG_FILE="$ADAPTER_DIR/adapter.log"
}
# 检查进程是否运行
process_exists() {
    local pid_file=$1
    local service_name=$2

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # 进程不存在但PID文件存在，清理PID文件
            rm -f "$pid_file"
            return 1
        fi
    fi
    return 1
}

# 保存PID到文件
save_pid() {
    local pid_file=$1
    local pid=$2
    echo "$pid" > "$pid_file"
}

# 删除PID文件
remove_pid() {
    local pid_file=$1
    [ -f "$pid_file" ] && rm -f "$pid_file"
}

check_service_status() {
    local service=$1
    local pid_file=$2

    case $service in
        "MaiBot")
            if process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
                echo -e "${GREEN}[运行中]${RESET}"
                return 0
            else
                echo -e "${RED}[已停止]${RESET}"
                return 1
            fi
            ;;
        "MaiBot-Napcat-Adapter")
            if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
                echo -e "${GREEN}[运行中]${RESET}"
                return 0
            else
                echo -e "${RED}[已停止]${RESET}"
                return 1
            fi
            ;;
    esac
}

press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
}

start_maibot() {
    info "正在启动 MaiBot..."

    if process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
        warn "MaiBot 已在运行中 (PID: $(cat "$MAIBOT_PID_FILE"))"
        return 1
    fi

    cd "$DEPLOY_DIR" || { error "无法进入目录 $DEPLOY_DIR"; return 1; }

    # 使用 nohup 启动并保存 PID
    # nohup bash -c "source .venv/bin/activate && python3 bot.py" >> "$MAIBOT_LOG_FILE" 2>&1 &
    nohup bash -c ".venv/bin/python3 bot.py" >> "$MAIBOT_LOG_FILE" 2>&1 &
    local pid=$!

    # 保存PID到文件
    save_pid "$MAIBOT_PID_FILE" "$pid"

    sleep 3

    if process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
        success "MaiBot 启动成功 (PID: $pid)"
        info "日志文件: $MAIBOT_LOG_FILE"
        return 0
    else
        error "MaiBot 启动失败,请检查日志: $MAIBOT_LOG_FILE"
        remove_pid "$MAIBOT_PID_FILE"
        return 1
    fi
}

start_adapter() {
    info "正在启动 MaiBot-Napcat-Adapter..."

    if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        warn "MaiBot-Napcat-Adapter 已在运行中 (PID: $(cat "$ADAPTER_PID_FILE"))"
        return 1
    fi

    cd "$ADAPTER_DIR" || { error "无法进入目录 $ADAPTER_DIR"; return 1; }

    # 使用 nohup 启动并保存 PID
    # nohup bash -c "source $DEPLOY_DIR/.venv/bin/activate && python3 main.py" >> "$ADAPTER_LOG_FILE" 2>&1 &
    nohup bash -c "$ADAPTER_venv/bin/python3 main.py" >> "$ADAPTER_LOG_FILE" 2>&1 &
    local pid=$!

    # 保存PID到文件
    save_pid "$ADAPTER_PID_FILE" "$pid"

    sleep 3

    if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        success "MaiBot-Napcat-Adapter 启动成功 (PID: $pid)"
        info "日志文件: $ADAPTER_LOG_FILE"
        return 0
    else
        error "MaiBot-Napcat-Adapter 启动失败,请检查日志: $ADAPTER_LOG_FILE"
        remove_pid "$ADAPTER_PID_FILE"
        return 1
    fi
}

stop_maibot() {
    info "正在停止 MaiBot..."

    if process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
        local pid=$(cat "$MAIBOT_PID_FILE")
        kill "$pid" 2>/dev/null

    # 等待进程结束
    local count=0
    while process_exists "$MAIBOT_PID_FILE" "MaiBot" && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done

    if process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
        warn "强制停止 MaiBot..."
        kill -9 "$pid" 2>/dev/null
        sleep 2
    fi

    if ! process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
        remove_pid "$MAIBOT_PID_FILE"
        success "MaiBot 已停止"
        return 0
    else
        error "MaiBot 停止失败"
        return 1
    fi
else
    warn "MaiBot 未运行"
    remove_pid "$MAIBOT_PID_FILE"
    return 1
    fi
}

stop_adapter() {
    info "正在停止 MaiBot-Napcat-Adapter..."

    if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        local pid=$(cat "$ADAPTER_PID_FILE")
        kill "$pid" 2>/dev/null

    # 等待进程结束
    local count=0
    while process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter" && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done

    if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        warn "强制停止 MaiBot-Napcat-Adapter..."
        kill -9 "$pid" 2>/dev/null
        sleep 2
    fi

    if ! process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        remove_pid "$ADAPTER_PID_FILE"
        success "MaiBot-Napcat-Adapter 已停止"
        return 0
    else
        error "MaiBot-Napcat-Adapter 停止失败"
        return 1
    fi
else
    warn "MaiBot-Napcat-Adapter 未运行"
    remove_pid "$ADAPTER_PID_FILE"
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

download_with_retry() {                                   #定义函数
    local url="$1"                                        #获取参数
    local output="$2"                                     #获取参数
    local max_attempts=3                                  #最大尝试次数
    local attempt=1                                       #当前尝试次数

    while [[ $attempt -le $max_attempts ]]; do            #循环直到达到最大尝试次数
        info "下载尝试 $attempt/$max_attempts: $url"       #打印信息日志
        if command_exists wget; then                      #如果 wget 存在
            if wget -O "$output" "$url" 2>/dev/null; then #使用 wget 下载
                success "下载成功: $output"                     #打印日志
                return 0                                  #成功返回
            fi                                            #结束条件判断
        elif command_exists curl; then                    #如果 curl 存在
            if curl -L -o "$output" "$url" 2>/dev/null; then #使用 curl 下载
                success "下载成功: $output"                         #打印日志
                return 0                                      #成功返回
            fi                                                #结束条件判断
        fi                                                    #结束条件判断
        warn "第 $attempt 次下载失败"                           #打印警告日志
        if [[ $attempt -lt $max_attempts ]]; then             #如果还没到最大尝试次数
            info "5秒后重试..."                                #打印信息日志
            sleep 5                                           #等待 5 秒
        fi                                                    #结束条件判断
        ((attempt++))                                         #增加尝试次数
    done                                                      #结束循环
    error "所有下载尝试都失败了"                                   #打印错误日志并退出
} 

# 查看日志
view_logs() {
    local service=$1
    local log_file=$2

    if [ ! -f "$log_file" ]; then
        error "日志文件不存在: $log_file"
        press_any_key
        return 1
    fi

    while true; do
        clear
        print_title "查看 $service 日志"

        echo -e "${CYAN}日志文件:${RESET} $log_file"
        echo -e "${CYAN}文件大小:${RESET} $(du -h "$log_file" | cut -f1)"
        echo ""

        echo -e "${BOLD}${YELLOW}选择查看方式:${RESET}"
        print_line
        echo -e "  ${BOLD}${GREEN}[1]${RESET} 最近50条"
        echo -e "  ${BOLD}${GREEN}[2]${RESET} 实时跟踪日志 (tail -f)"
        echo -e "  ${BOLD}${GREEN}[3]${RESET} 使用 less 分页查看"
        echo -e "  ${BOLD}${GREEN}[0]${RESET} 返回主菜单"
        print_line
        echo ""
        echo -ne "${BOLD}${YELLOW}请选择操作 [0-3]: ${RESET}"

        read log_choice
        case $log_choice in
            1)
                clear
                print_title "$service - 日志查看"
                echo -e "${YELLOW}提示: 使用方向键滚动，按 q 退出${RESET}"
                echo ""
                tail -n 50 "$log_file" | less -RG
                ;;
            2)
                clear
                print_title "$service - 实时日志跟踪"
                echo -e "${YELLOW}提示: 按 Ctrl+C 停止跟踪${RESET}"
                echo ""
                tail -f "$log_file"
                ;;
            3)
                clear
                print_title "$service - 分页查看"
                echo -e "${YELLOW}提示:${RESET}"
                echo -e "  ${YELLOW}• 使用方向键/PageUp/PageDown 翻页${RESET}"
                echo -e "  ${YELLOW}• 使用 / 搜索内容${RESET}"
                echo -e "  ${YELLOW}• 按 q 退出${RESET}"
                echo ""
                less -RG "$log_file"
                ;;
            0)
                return 0
                ;;
            *)
                error "无效选项"
                sleep 1
                ;;
        esac
    done
}

install_plugins() {
    echo -ne "${BOLD}${YELLOW}请输入插件仓库地址："
    read plugin_url
    plugin_name=$(basename "$plugin_url" .git)
    info "开始克隆插件$plugin_name"
    if [ -d "$PLUGIN_DIR/$plugin_name" ]; then # 如果目录已存在
        warn "检测到插件$plugin_name已存在。是否删除并重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$PLUGIN_DIR/$plugin_name" # 删除插件
            success "已删除$plugin_name" # 提示用户已删除
        else # 如果用户选择不删除
            warn "已取消$plugin_name的克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
    git clone --depth 1 "$plugin_url" "$PLUGIN_DIR/$plugin_name" # 克隆仓库

    info "激活虚拟环境"
    source "$DEPLOY_DIR/.venv/bin/activate"
    info "开始安装插件依赖"
    if pip install -r $PLUGIN_DIR/$plugin_name/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple; then
        deactivate
        success "$plugin_name 依赖安装成功"
        info "显示$plugin_name的README"
        cat $PLUGIN_DIR/$plugin_name/README.md
        info "README已显示"
        press_any_key
        break
    else
        deactivate
        warn "$plugin_name 依赖安装失败"
        press_any_key
    fi

}

select_github_proxy() {                                               #定义函数
    print_title "选择 GitHub 代理"                                     #打印标题
    echo "请根据您的网络环境选择一个合适的下载代理："                        #打印提示
    echo                                                             #打印空行

    # 使用 select 提供选项
    select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
        case $proxy_choice in
            "ghfast.top 镜像 (推荐)") 
                GITHUB_PROXY="https://ghfast.top/"; 
                success "已选择: ghfast.top 镜像" 
                break
                ;;
            "ghproxy.net 镜像") 
                GITHUB_PROXY="https://ghproxy.net/"; 
                success "已选择: ghproxy.net 镜像" 
                break
                ;;
            "不使用代理") 
                GITHUB_PROXY=""; 
                success "已选择: 不使用代理" 
                break
                ;;
            "自定义代理") 
                # 允许用户输入自定义代理
                read -p "请输入自定义 GitHub 代理 URL (必须以斜杠 / 结尾): " custom_proxy
                # 检查自定义代理是否以斜杠结尾
                if [[ -n "$custom_proxy" && "$custom_proxy" != */ ]]; then
                    custom_proxy="${custom_proxy}/" # 如果没有斜杠，自动添加
                    warn "自定义代理 URL 没有以斜杠结尾，已自动添加斜杠"
                fi
                GITHUB_PROXY="$custom_proxy"
                success "已选择: 自定义代理 - $GITHUB_PROXY"
                break
                ;;
            *) 
                warn "无效输入，使用默认代理"
                GITHUB_PROXY="https://ghfast.top/"
                ok "已选择: ghfast.top 镜像 (默认)"
                break
                ;;
        esac
    done
}

updata_maimai(){
    local original_dir="$PWD"

    cd "$DEPLOY_DIR" || error "无法进入 MaiBot 目录"

    info "正在备份data和config"
    if [ -d "../backup" ]; then # 如果目录已存在
        info "备份文件夹已存在"
    else 
        mkdir -p "../backup"
    fi 
    cp -r ./config "../backup/"
    cp -r ./data "../backup/"
    cp -r ./plugins "../backup/"

    select_github_proxy

    info "开始拉取远程仓库"

    git pull

    info "激活虚拟环境"
    source "$DEPLOY_DIR/.venv/bin/activate"
    info "开始安装依赖"
    # 安装 MaiBot 依赖
    attempt=1
    while [[ $attempt -le 3 ]]; do
        if [[ -f "requirements.txt" ]]; then
            if pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple --upgrade; then
                success "MaiBot 依赖安装成功"
                break
            else
                warn "MaiBot 依赖安装失败,重试 $attempt/3"
                ((attempt++))
                sleep 5
            fi
        else
            error "未找到 requirements.txt 文件"
        fi
    done

    if [[ $attempt -gt 3 ]]; then
        error "MaiBot 依赖安装多次失败"
    fi
    deactivate
    info "更新已结束"
    press_any_key
}

list_plugins() {
    print_title "已安装插件列表"
    
    if [ ! -d "$PLUGIN_DIR" ] || [ -z "$(ls -A "$PLUGIN_DIR")" ]; then
        warn "未安装任何插件"
        return
    fi
    
    local count=0
    for plugin in "$PLUGIN_DIR"/*; do
        if [ -d "$plugin" ]; then
            count=$((count + 1))
            plugin_name=$(basename "$plugin")
            echo -e "${BOLD}${GREEN}$count. $plugin_name${RESET}"
            
            # 显示 git 信息
            if [ -d "$plugin/.git" ]; then
                (
                    cd "$plugin" || exit 1
                    local git_url=$(git remote get-url origin 2>/dev/null || echo "未知")
                    local git_branch=$(git branch --show-current 2>/dev/null || echo "未知")
                    local git_commit=$(git log -1 --format="%h %ad" --date=short 2>/dev/null || echo "未知")
                    
                    # 修复版本检查逻辑
                    local remote_info=""
                    if git remote get-url origin &>/dev/null; then
                        # 获取本地最新提交的完整哈希
                        local local_commit_full=$(git rev-parse HEAD 2>/dev/null)
                        # 获取远程最新提交的完整哈希
                        local remote_commit_full=$(git ls-remote origin HEAD 2>/dev/null | cut -f1)
                        
                        if [ -n "$local_commit_full" ] && [ -n "$remote_commit_full" ]; then
                            # 比较完整哈希
                            if [ "$local_commit_full" = "$remote_commit_full" ]; then
                                remote_info="${GREEN}已是最新版本${RESET}"
                            else
                                # 检查领先/落后情况
                                git fetch origin >/dev/null 2>&1
                                local ahead_behind=$(git rev-list --left-right --count HEAD...origin/HEAD 2>/dev/null)
                                if [ -n "$ahead_behind" ]; then
                                    local ahead=$(echo "$ahead_behind" | cut -f1)
                                    local behind=$(echo "$ahead_behind" | cut -f2)
                                    if [ "$behind" -gt 0 ]; then
                                        remote_info="${YELLOW}落后 $behind 个提交${RESET}"
                                    elif [ "$ahead" -gt 0 ]; then
                                        remote_info="${CYAN}领先 $ahead 个提交${RESET}"
                                    else
                                        remote_info="${YELLOW}分支已分叉${RESET}"
                                    fi
                                else
                                    remote_info="${YELLOW}有更新可用${RESET}"
                                fi
                            fi
                        else
                            remote_info="${RED}无法获取提交信息${RESET}"
                        fi
                    else
                        remote_info="${RED}无远程仓库${RESET}"
                    fi
                    
                    echo -e "   ${BLUE}仓库:${RESET} $git_url"
                    echo -e "   ${BLUE}分支:${RESET} $git_branch"
                    echo -e "   ${BLUE}最新提交:${RESET} $git_commit"
                    echo -e "   ${BLUE}远程状态:${RESET} $remote_info"
                )
            else
                echo -e "   ${RED}⚠ 非Git仓库${RESET}"
            fi
            
            # 检查配置文件
            if [ -f "$plugin/config.toml" ]; then
                echo -e "   ${GREEN}✓ 配置文件已存在${RESET}"
            else
                echo -e "   ${YELLOW}⚠ 无配置文件，请重启MaiBot${RESET}"
            fi
            
            echo
        fi
    done
    echo -e "${BOLD}总计: $count 个插件${RESET}"
}

updata_plugin(){
    info "列出插件文件……"
    ls $PLUGIN_DIR
    echo -ne "${BOLD}${YELLOW}请输入要更新的插件: ${RESET}"
    read plugin_name
    cd $PLUGIN_DIR/$plugin_name
    info "开始拉取更新"
    git pull
    info "显示当前git版本状态"
    list_plugins
    info "激活虚拟环境"
    source "$DEPLOY_DIR/.venv/bin/activate"
    info "开始更新插件依赖"
    if pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple --upgrade; then
        deactivate
        success "$plugin_name 依赖更新成功"
        break
    else
        deactivate
        warn "$plugin_name 依赖更新失败"
        press_any_key
    fi
    press_any_key
}

# 清理日志
clean_logs() {
    local service=$1
    local log_file=$2
    local pid_file=$3

    if [ -f "$log_file" ]; then
        > "$log_file"
        success "已清空 $service 日志"
    else
        warn "$service 日志文件不存在"
    fi

    # 清理无效的PID文件
    if [ -f "$pid_file" ] && ! process_exists "$pid_file" "$service"; then
        remove_pid "$pid_file"
        info "已清理无效的 $service PID文件"
    fi
}

# 显示菜单
show_menu() {
    clear
    print_title "MaiBot 管理面板 2025.10.06"

    echo -e "${CYAN}系统信息:${RESET}"
    echo -e "  用户: ${GREEN}$CURRENT_USER${RESET}"
    echo -e "  时间: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "  路径: ${GREEN}$DEPLOY_BASE${RESET}"
    echo ""

    echo -e "${CYAN}服务状态:${RESET}"
    echo -e "  MaiBot:                 $(check_service_status 'MaiBot' "$MAIBOT_PID_FILE")"
    echo -e "  MaiBot-Napcat-Adapter:  $(check_service_status 'MaiBot-Napcat-Adapter' "$ADAPTER_PID_FILE")"
    echo ""

    # 显示PID信息
    if [ -f "$MAIBOT_PID_FILE" ] && process_exists "$MAIBOT_PID_FILE" "MaiBot"; then
        echo -e "  MaiBot PID:  ${GREEN}$(cat "$MAIBOT_PID_FILE")${RESET}"
    fi
    if [ -f "$ADAPTER_PID_FILE" ] && process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        echo -e "  Adapter PID: ${GREEN}$(cat "$ADAPTER_PID_FILE")${RESET}"
    fi
    echo ""

    print_line
    echo -e "${BOLD}${YELLOW}操作菜单:${RESET}"
    print_line

    echo -e "  ${BOLD}${GREEN}[1]  ${RESET} 启动所有服务 (MaiBot + Adapter)"
    echo -e "  ${BOLD}${GREEN}[2]  ${RESET} 停止所有服务"
    echo ""
    echo -e "  ${BOLD}${GREEN}[3]  ${RESET} 仅启动 MaiBot"
    echo -e "  ${BOLD}${GREEN}[4]  ${RESET} 仅启动 MaiBot-Napcat-Adapter"
    echo ""
    echo -e "  ${BOLD}${GREEN}[5]  ${RESET} 仅停止 MaiBot"
    echo -e "  ${BOLD}${GREEN}[6]  ${RESET} 仅停止 MaiBot-Napcat-Adapter"
    echo ""
    echo -e "  ${BOLD}${GREEN}[7]  ${RESET} 前台启动 MaiBot"
    echo -e "  ${BOLD}${GREEN}[8]  ${RESET} 前台启动 MaiBot-Napcat-Adapter"
    echo ""
    echo -e "  ${BOLD}${GREEN}[9]  ${RESET} 查看 MaiBot 日志"
    echo -e "  ${BOLD}${GREEN}[10] ${RESET} 查看 MaiBot-Napcat-Adapter 日志"
    echo ""
    echo -e "  ${BOLD}${GREEN}[11] ${RESET} 清理 MaiBot 日志和PID"
    echo -e "  ${BOLD}${GREEN}[12] ${RESET} 清理 MaiBot-Napcat-Adapter 日志和PID"
    echo ""
    echo -e "  ${BOLD}${GREEN}[13/19] ${RESET} 安装/更新插件"
    echo -e "  ${BOLD}${GREEN}[14] ${RESET} 列出所有已安装的插件"
    echo -e "  ${BOLD}${GREEN}[15] ${RESET} 更新麦麦"
    echo -e "  ${BOLD}${GREEN}[16] ${RESET} 更新脚本"
    echo -e "  ${BOLD}${GREEN}[17] ${RESET} 导入openie"
    echo -e "  ${BOLD}${GREEN}[18] ${RESET} 安装依赖"
    echo ""
    echo -e "  ${BOLD}${GREEN}[0]  ${RESET} 退出脚本"

    print_line
    echo ""
    echo -ne "${BOLD}${YELLOW}请选择操作 [0-18]: ${RESET}"
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
                print_title "启动 MaiBot"
                start_maibot
                press_any_key
                ;;
            4) 
                print_title "启动 MaiBot-Napcat-Adapter"
                start_adapter
                press_any_key
                ;;
            5) 
                print_title "停止 MaiBot"
                stop_maibot
                press_any_key
                ;;
            6) 
                print_title "停止 MaiBot-Napcat-Adapter"
                stop_adapter
                press_any_key
                ;;
            7)
                cd $DEPLOY_DIR && source .venv/bin/activate && python3 bot.py
                press_any_key 
                ;;
            8)
                cd $ADAPTER_DIR && source $ADAPTER_venv/bin/activate && python3 main.py
                press_any_key 
                ;;
            9) 
                view_logs "MaiBot" "$MAIBOT_LOG_FILE"
                ;;
            10) 
                view_logs "MaiBot-Napcat-Adapter" "$ADAPTER_LOG_FILE"
                ;;
            11) 
                print_title "清理 MaiBot"
                clean_logs "MaiBot" "$MAIBOT_LOG_FILE" "$MAIBOT_PID_FILE"
                press_any_key
                ;;
            12) 
                print_title "清理 MaiBot-Napcat-Adapter"
                clean_logs "MaiBot-Napcat-Adapter" "$ADAPTER_LOG_FILE" "$ADAPTER_PID_FILE"
                press_any_key
                ;;
            13)
                install_plugins
                ;;
            14) list_plugins; press_any_key ;;    
            15)
                updata_maimai
                ;;
            16)
                local DOWNLOAD_URL="${GITHUB_PROXY}https://github.com/kanfandelong/maimai_install/raw/main/maibot.sh"
                local TARGET_FILE="$TARGET_DIR/maibot"  # 修正文件路径
                select_github_proxy
                # 下载 maibot 脚本
                download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE"
                ;;
            17)
                cd $DEPLOY_DIR && source .venv/bin/activate && python3 ./scripts/import_openie.py
                press_any_key 
                ;;
            18)
                echo -ne "${BOLD}${YELLOW}请输入包名："
                read Package_name
                info "激活虚拟环境"
                source "$DEPLOY_DIR/.venv/bin/activate"
                info "开始安装$Package_name"
                if pip install $Package_name -i https://pypi.tuna.tsinghua.edu.cn/simple; then
                    deactivate
                    success "$Package_name 安装成功"
                    press_any_key
                else
                    deactivate
                    warn "$Package_name 安装失败"
                    press_any_key
                fi
                ;;
            19)
                updata_plugin
                ;;
            114514) 
                echo "原始脚本仓库https://github.com/Astriora/Antlia 本脚本仓库地址https://github.com/kanfandelong/maimai_install" 
                press_any_key  
                ;;
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
