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
	
	if [ -d "$DEPLOY_DIR/.venv" ]; then
        DEPLOY_venv=$DEPLOY_DIR/.venv
    else
		if [ -d "$DEPLOY_DIR/venv" ]; then
			DEPLOY_venv=$DEPLOY_DIR/venv
		else
			warn "没有找到MaiBot的虚拟环境"
			sleep 3
			exit 1
		fi
    fi
	
    if [ -d "$ADAPTER_DIR/.venv" ]; then
        ADAPTER_venv=$ADAPTER_DIR/.venv
    else
        if [ -d "$ADAPTER_DIR/venv" ]; then
			ADAPTER_venv=$ADAPTER_DIR/venv
		else
			if [ -d "$DEPLOY_venv" ]; then
				ADAPTER_venv=$DEPLOY_venv
			else
				warn "没有找到适配器的虚拟环境"
				sleep 3
				exit 1
			fi
		fi
    fi
    
    
	TTS_venv="$DEPLOY_venv"
	TTS_DIR="$DEPLOY_BASE/maimbot_tts_adapter"
	TTS_LOG_FILE="$TTS_DIR/tts.log"
	TTS_PID_FILE="$TTS_DIR/tts.pid"
	
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
                echo -e "${GREEN}[运行中]  ${RESET}PID: ${GREEN}$(cat "$2")${RESET}"
                return 0
            else
                echo -e "${RED}[已停止]${RESET}"
                return 1
            fi
            ;;
        "MaiBot-Napcat-Adapter")
            if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
                echo -e "${GREEN}[运行中]  ${RESET}PID: ${GREEN}$(cat "$2")${RESET}"
                return 0
            else
                echo -e "${RED}[已停止]${RESET}"
                return 1
            fi
            ;;
        "MaiBot-TTS-Adapter")
            if process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter"; then
                echo -e "${GREEN}[运行中]  ${RESET}PID: ${GREEN}$(cat "$2")${RESET}"
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
    nohup unbuffer bash -c "$DEPLOY_venv/bin/python3 bot.py" >> "$MAIBOT_LOG_FILE" 2>&1 &
    local pid=$!

    # 保存PID到文件
    save_pid "$MAIBOT_PID_FILE" "$pid"

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
    if [ "$current_use_tts" = "true" ]; then
        start_tts
    fi
    info "正在启动 MaiBot-Napcat-Adapter..."

    if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        warn "MaiBot-Napcat-Adapter 已在运行中 (PID: $(cat "$ADAPTER_PID_FILE"))"
        return 1
    fi

    cd "$ADAPTER_DIR" || { error "无法进入目录 $ADAPTER_DIR"; return 1; }

    # 使用 nohup 启动并保存 PID
    # nohup bash -c "source $DEPLOY_DIR/.venv/bin/activate && python3 main.py" >> "$ADAPTER_LOG_FILE" 2>&1 &
    nohup unbuffer bash -c "$ADAPTER_venv/bin/python3 main.py" >> "$ADAPTER_LOG_FILE" 2>&1 &
    local pid=$!

    # 保存PID到文件
    save_pid "$ADAPTER_PID_FILE" "$pid"

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

start_tts() {
    info "正在启动 MaiBot-TTS-Adapter..."

    if process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter"; then
        warn "MaiBot-TTS-Adapter 已在运行中 (PID: $(cat "$TTS_PID_FILE"))"
    fi

    cd "$TTS_DIR" || { error "无法进入目录 $TTS_DIR"; return 1; }

    # 使用 nohup 启动并保存 PID
    # nohup bash -c "source $DEPLOY_DIR/.venv/bin/activate && python3 main.py" >> "$ADAPTER_LOG_FILE" 2>&1 &
    nohup unbuffer bash -c "$TTS_venv/bin/python3 main.py" >> "$TTS_LOG_FILE" 2>&1 &
    local pid=$!

    # 保存PID到文件
    save_pid "$TTS_PID_FILE" "$pid"

    if process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter"; then
        success "MaiBot-TTS-Adapter 启动成功 (PID: $pid)"
        info "日志文件: $TTS_LOG_FILE"
    else
        error "MaiBot-TTS-Adapter 启动失败,请检查日志: $TTS_LOG_FILE"
        remove_pid "$TTS_PID_FILE"
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
    stop_tts
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

stop_tts() {
    info "正在停止 MaiBot-TTS-Adapter..."

    if process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter"; then
        local pid=$(cat "$TTS_PID_FILE")
        kill "$pid" 2>/dev/null

        # 等待进程结束
        local count=0
        while process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter" && [ $count -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done
    
        if process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter"; then
            warn "强制停止 MaiBot-TTS-Adapter..."
            kill -9 "$pid" 2>/dev/null
            sleep 2
        fi
    
        if ! process_exists "$TTS_PID_FILE" "MaiBot-TTS-Adapter"; then
            remove_pid "$TTS_PID_FILE"
            success "MaiBot-TTS-Adapter 已停止"
        else
            error "MaiBot-TTS-Adapter 停止失败"
        fi
    else
        warn "MaiBot-TTS-Adapter 未运行"
        remove_pid "$TTS_PID_FILE"
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
    select_github_proxy
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
    git clone "${GITHUB_PROXY}$plugin_url" "$PLUGIN_DIR/$plugin_name" # 克隆仓库

    info "激活虚拟环境"
	if [ -d "$DEPLOY_venv" ]; then
		source "$DEPLOY_venv/bin/activate"
	else
		warn "没有找到虚拟环境"
		return
	fi
    info "开始安装插件依赖"
    if pip install -r $PLUGIN_DIR/$plugin_name/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple; then
        deactivate
        success "$plugin_name 依赖安装成功"
        info "显示$plugin_name的README"
        cat $PLUGIN_DIR/$plugin_name/README.md
        info "README已显示"
        return
    else
        deactivate
        warn "使用pip 安装 $plugin_name 依赖失败"
		read -p "要使用uv重试吗(y/n, 默认y): " del_choice 
        del_choice=${del_choice:-y}
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then
			cd $DEPLOY_DIR
			uv venv
            if uv pip install -r $PLUGIN_DIR/$plugin_name/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple; then
				success "$plugin_name 依赖安装成功"
				info "显示$plugin_name的README"
				cat $PLUGIN_DIR/$plugin_name/README.md
				info "README已显示"
				return
			else
				warn "$plugin_name 依赖未能安装"
				return
			fi
        else
            warn "$plugin_name 依赖未能安装"
            return
        fi
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
        rm -rf ../backup/*
    else 
        mkdir -p "../backup"
    fi 
    cp -r ./config "../backup/"
    cp -r ./data "../backup/"
    cp -r ./plugins "../backup/"

    info "开始处理Git更新"

    # 检查是否有本地修改
    if git diff --quiet && git diff --staged --quiet; then
        info "没有本地修改，直接拉取更新"
    else
        info "保存本地修改..."
        git stash push -m "auto-update-local-changes-$(date +%Y%m%d-%H%M%S)"
    fi

    info "拉取远程仓库最新代码..."
    git pull --force

    # 如果有保存的stash，则尝试恢复
    if git stash list | grep -q "auto-update-local-changes"; then
        info "恢复本地修改并尝试合并..."
        if git stash pop; then
            success "本地修改已成功合并"
        else
            warn "自动合并出现冲突，需要手动解决"
            info "请手动执行以下命令来解决冲突："
            info "1. 查看冲突文件: git diff --name-only --diff-filter=U"
            info "2. 手动编辑冲突文件解决冲突"
            info "3. 标记冲突已解决: git add <冲突文件>"
            info "4. 完成合并: git stash drop"
        fi
    fi

    info "激活虚拟环境"
    source "$DEPLOY_venv/bin/activate"
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
    
    # 定义要排除的文件夹模式
    local exclude_patterns=("__pycache__" "*.pyc" "*.pyo" "*.pyd" ".*.swp" ".*.swo" ".git" "__MACOSX" ".DS_Store")
    
    local count=0
    for plugin in "$PLUGIN_DIR"/*; do
        if [ -d "$plugin" ]; then
            local plugin_name=$(basename "$plugin")
            
            # 检查是否在排除列表中
            local skip=0
            for pattern in "${exclude_patterns[@]}"; do
                if [[ "$plugin_name" == $pattern ]]; then
                    skip=1
                    break
                fi
            done
            
            # 跳过隐藏文件和非插件目录
            if [[ $skip -eq 1 || "$plugin_name" == .* || ! -f "$plugin/plugin.py" ]]; then
                continue
            fi
            
            count=$((count + 1))
            echo -e "${BOLD}${GREEN}$count. $plugin_name${RESET}"
            echo -en "   ${BLUE}[INFO]${RESET} 正在检查插件信息......\r"
            
            # 显示 git 信息
            if [ -d "$plugin/.git" ]; then
                (
                    cd "$plugin" || exit 1
                    local git_url=$(git remote get-url origin 2>/dev/null | sed 's|https://github.com/||; s|git@github.com:||; s|\.git$||' || echo "未知")
                    local git_branch=$(git branch --show-current 2>/dev/null || echo "未知")
                    
                    # 获取详细的提交信息
                    local git_commit_hash=$(git log -1 --format="%h" 2>/dev/null || echo "未知")
                    local git_commit_date=$(git log -1 --format="%cd" --date=format:"%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
                    local git_commit_msg=$(git log -1 --format="%s" 2>/dev/null | head -c 50)
                    if [ ${#git_commit_msg} -eq 50 ]; then
                        git_commit_msg="${git_commit_msg}..."
                    fi
                    
                    local remote_info=""
                    local status_details=""
                    local behind=0
                    local ahead=0
                    
                    if git remote get-url origin &>/dev/null; then
                        # 获取本地和远程的提交信息
                        local local_commit_full=$(git rev-parse HEAD 2>/dev/null)
                        git fetch origin --quiet >/dev/null 2>&1
                        
                        # 检查分支是否有效
                        if [ -n "$git_branch" ] && [ "$git_branch" != "未知" ]; then
                            local remote_commit_full=$(git rev-parse "origin/$git_branch" 2>/dev/null)
                            
                            if [ -n "$local_commit_full" ] && [ -n "$remote_commit_full" ]; then
                                if [ "$local_commit_full" = "$remote_commit_full" ]; then
                                    remote_info="${GREEN}✅ 已同步${RESET}"
                                    status_details="本地与远程版本一致"
                                else
                                    # 检查领先/落后情况
                                    local ahead_behind=$(git rev-list --left-right --count "origin/$git_branch...HEAD" 2>/dev/null)
                                    if [ -n "$ahead_behind" ] && [[ "$ahead_behind" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
                                        behind=$(echo "$ahead_behind" | cut -f1)  # 远程领先的提交数
                                        ahead=$(echo "$ahead_behind" | cut -f2)   # 本地领先的提交数
                                        
                                        if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ]; then
                                            remote_info="${YELLOW}⬇ 落后 $behind 个提交${RESET}"
                                            status_details="建议执行 git pull 更新"
                                        elif [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ]; then
                                            remote_info="${CYAN}⬆ 领先 $ahead 个提交${RESET}"
                                            status_details="本地有未推送的修改"
                                        elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
                                            remote_info="${MAGENTA}🔀 分叉 (领先$ahead,落后$behind)${RESET}"
                                            status_details="需要解决合并冲突"
                                        else
                                            remote_info="${YELLOW}⚠ 状态异常${RESET}"
                                        fi
                                    else
                                        remote_info="${YELLOW}🔄 有更新可用${RESET}"
                                        status_details="无法精确比较提交历史"
                                    fi
                                    
                                    # 显示远程更新信息（只在behind是数字且大于0时）
                                    if [[ "$behind" =~ ^[0-9]+$ ]] && [ "$behind" -gt 0 ]; then
                                        local remote_commit_msg=$(git log -1 --format="%s" "origin/$git_branch" 2>/dev/null | head -c 40)
                                        status_details="$status_details | 远程最新: $remote_commit_msg"
                                    fi
                                fi
                            else
                                if [ -z "$local_commit_full" ]; then
                                    remote_info="${RED}❌ 无法获取本地提交${RESET}"
                                    status_details="仓库可能为空或损坏"
                                else
                                    remote_info="${YELLOW}⚠ 远程分支不存在${RESET}"
                                    status_details="分支 '$git_branch' 在远程不存在"
                                fi
                            fi
                        else
                            remote_info="${YELLOW}⚠ 无法确定分支${RESET}"
                            status_details="Git仓库可能处于分离头指针状态"
                        fi
                    else
                        remote_info="${RED}🌐 无远程仓库${RESET}"
                        status_details="此插件未关联远程仓库"
                    fi
                    
                    # 检查工作区状态
                    local worktree_status=""
                    if ! git diff --quiet 2>/dev/null; then
                        worktree_status="${YELLOW}⚡ 有未暂存修改${RESET}"
                    elif ! git diff --cached --quiet 2>/dev/null; then
                        worktree_status="${YELLOW}📝 有已暂存修改${RESET}"
                    else
                        worktree_status="${GREEN}📁 工作区干净${RESET}"
                    fi
                    
                    echo -e "   ${BLUE}📦 仓库:${RESET} $git_url"
                    echo -e "   ${BLUE}🌿 分支:${RESET} $git_branch"
                    echo -e "   ${BLUE}📎 最新提交:${RESET} $git_commit_hash | $git_commit_date"
                    echo -e "   ${BLUE}💬 提交信息:${RESET} $git_commit_msg"
                    echo -e "   ${BLUE}🔄 同步状态:${RESET} $remote_info"
                    echo -e "   ${BLUE}📋 工作区:${RESET} $worktree_status"
                    if [ -n "$status_details" ]; then
                        echo -e "   ${BLUE}ℹ️  详情:${RESET} $status_details"
                    fi
                )
            else
                echo -e "   ${RED}⚠ 非Git仓库                             ${RESET}"
                # 尝试显示目录信息
                local file_count=$(find "$plugin" -name "*.py" -type f | wc -l)
                local dir_size=$(du -sh "$plugin" 2>/dev/null | cut -f1)
                echo -e "   ${BLUE}📊 文件统计:${RESET} $file_count 个Python文件"
                echo -e "   ${BLUE}📁 目录大小:${RESET} $dir_size"
            fi
            
            # 检查配置文件
            if [ -f "$plugin/config.toml" ] || [ -f "$plugin/config.py" ] || [ -f "$plugin/config.json" ]; then
                local config_files=""
                [ -f "$plugin/config.toml" ] && config_files="$config_files config.toml"
                [ -f "$plugin/config.py" ] && config_files="$config_files config.py"
                [ -f "$plugin/config.json" ] && config_files="$config_files config.json"
                echo -e "   ${GREEN}✅ 配置文件:${RESET}${config_files}"
            else
                echo -e "   ${YELLOW}⚠ 无配置文件${RESET}"
            fi
            
            # 检查依赖文件
            if [ -f "$plugin/requirements.txt" ]; then
                local req_count=$(wc -l < "$plugin/requirements.txt" 2>/dev/null)
                echo -e "   ${BLUE}📦 依赖:${RESET} $req_count 个包 (requirements.txt)"
            fi
            
            echo
        fi
    done
    
    if [ $count -eq 0 ]; then
        warn "未找到有效的插件目录"
    else
        echo -e "${BOLD}总计: $count 个插件${RESET}"
    fi
}

updata_plugin(){
    info "列出插件文件……"
    ls $PLUGIN_DIR
    echo -ne "${BOLD}${YELLOW}请输入要更新的插件: ${RESET}"
    read _plugin_name
    cd $PLUGIN_DIR/$_plugin_name
    info "开始拉取更新"
    git pull
    info "显示当前git版本状态"
    list_plugins
    info "激活虚拟环境"
    source "$DEPLOY_venv/bin/activate"
    info "开始更新插件依赖"
    if pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple --upgrade; then
        deactivate
        success "$_plugin_name 依赖更新成功"
    else
        deactivate
        warn "$_plugin_name 依赖更新失败"
    fi
    press_any_key
}

switch_plugin_version(){
    info "列出插件文件……"
    ls $PLUGIN_DIR
    echo -ne "${BOLD}${YELLOW}请输入要切换版本的插件: ${RESET}"
    read plugin_name
    
    if [ ! -d "$PLUGIN_DIR/$plugin_name" ]; then
        error "插件 $plugin_name 不存在"
        press_any_key
        return 1
    fi
    
    cd $PLUGIN_DIR/$plugin_name
    
    # 检查是否是git仓库
    if [ ! -d ".git" ]; then
        error "该目录不是git仓库，无法切换版本"
        press_any_key
        return 1
    fi
    
    info "获取远程信息……"
    git fetch --all
    
    # 获取tag列表并按版本排序
    tags=$(git tag -l | sort -V)
    
    echo -e "\n${BOLD}${CYAN}可用的版本选项:${RESET}"
    i=1
    declare -A version_map
    
    # 添加"最新提交"选项
    echo "  $i. 📌 最新提交 (main/master分支)"
    version_map[$i]="latest"
    ((i++))
    
    # 显示tag列表
    for tag in $tags; do
        echo "  $i. 🏷️  $tag"
        version_map[$i]=$tag
        ((i++))
    done
    
    current_branch=$(git branch --show-current)
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "无")
    echo -e "\n${BOLD}当前状态:${RESET} 分支: $current_branch, Tag: $current_tag"
    
    echo -ne "\n${BOLD}${YELLOW}请选择要切换的版本编号: ${RESET}"
    read version_choice
    
    if [ -z "${version_map[$version_choice]}" ]; then
        error "无效的选择: $version_choice"
        press_any_key
        return 1
    fi
    
    selected_version="${version_map[$version_choice]}"
    
    if [ "$selected_version" = "latest" ]; then
        # 切换到最新提交
        info "正在切换到最新提交..."
        
        # 尝试切换到main或master分支
        if git show-ref --verify --quiet refs/heads/main; then
            git checkout main
        elif git show-ref --verify --quiet refs/heads/master; then
            git checkout master
        else
            # 如果都没有，获取默认分支
            default_branch=$(git remote show origin | grep "HEAD branch" | cut -d" " -f5)
            if [ -n "$default_branch" ]; then
                git checkout $default_branch
            else
                error "无法确定默认分支"
                press_any_key
                return 1
            fi
        fi
        
        # 拉取最新更改
        git pull origin $(git branch --show-current)
        
        success "已切换到最新提交"
        current_commit=$(git log --oneline -1 --format="%h %s")
        info "当前提交: $current_commit"
        
    else
        # 切换到指定tag
        info "正在切换到 tag: $selected_version"
        
        # 先切换到master/main分支以便可以切换tag
        git checkout main 2>/dev/null || git checkout master 2>/dev/null || git checkout -q $(git rev-parse HEAD)
        
        if git checkout "tags/$selected_version" 2>/dev/null || git checkout "$selected_version" 2>/dev/null; then
            success "成功切换到版本: $selected_version"
            current_commit=$(git log --oneline -1)
            info "当前提交: $current_commit"
        else
            error "切换版本失败: $selected_version"
            press_any_key
            return 1
        fi
    fi
    
    # 激活虚拟环境并更新依赖
    info "激活虚拟环境"
    source "$DEPLOY_venv/bin/activate"
    info "开始更新插件依赖"
    
    if pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple --upgrade; then
        deactivate
        success "$plugin_name 依赖更新成功"
    else
        deactivate
        warn "$plugin_name 依赖更新失败"
        press_any_key
    fi
    
    # 显示插件列表确认
    list_plugins
    
    press_any_key
}

switch_adapter_mode() {
    print_title "切换适配器模式"
    
    local config_file="$ADAPTER_DIR/config.toml"
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        error "配置文件不存在: $config_file"
        return 1
    fi
    
    # 读取当前配置
    local current_port=$(grep -E '^port\s*=' "$config_file" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    local current_use_tts=$(grep -E '^use_tts\s*=' "$config_file" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    
    info "当前配置:"
    echo -e "  ${CYAN}端口 (第15行):${RESET} $current_port"
    echo -e "  ${CYAN}使用TTS (第27行):${RESET} $current_use_tts"
    echo ""
    
    # 显示模式选择
    echo -e "${BOLD}${YELLOW}选择模式:${RESET}"
    print_line
    echo -e "  ${BOLD}${GREEN}[1]${RESET} 普通模式 (port = 8000, use_tts = false)"
    echo -e "  ${BOLD}${GREEN}[2]${RESET} TTS模式 (port = 8070, use_tts = true)"
    print_line
    echo ""
    echo -ne "${BOLD}${YELLOW}请选择模式 [1-2]: ${RESET}"
    
    read mode_choice
    
    case $mode_choice in
        1)
            # 切换到普通模式
            sed -i '15s/.*/port = 8000/' "$config_file"
            sed -i '27s/.*/use_tts = false/' "$config_file"
            success "已切换到普通模式"
            info "配置已更新: port = 8000, use_tts = false"
            ;;
        2)
            # 切换到TTS模式
            sed -i '15s/.*/port = 8070/' "$config_file"
            sed -i '27s/.*/use_tts = true/' "$config_file"
            success "已切换到TTS模式"
            info "配置已更新: port = 8070, use_tts = true"
            ;;
        *)
            error "无效选择"
            return 1
            ;;
    esac
    
    # 检查适配器是否在运行，如果在运行则提示重启
    if process_exists "$ADAPTER_PID_FILE" "MaiBot-Napcat-Adapter"; then
        echo ""
        warn "适配器正在运行中，配置更改需要重启才能生效"
        echo -ne "${BOLD}${YELLOW}是否立即重启适配器? [y/N]: ${RESET}"
        read restart_choice
        restart_choice=${restart_choice:-n}
        
        if [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
            stop_adapter
            sleep 2
            start_adapter
        else
            info "请记得手动重启适配器以使配置生效"
        fi
    fi
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

import_knowledge() {
    echo -ne "${BOLD}${YELLOW}请输入一段用于导入知识库的文本（直接回车/换行表示直接提取并导入lpmm_raw_data中存放的txt）："
    read knowledge
    if [ -z "$knowledge" ]; then
        info "从lpmm_raw_data中存放的txt文本提取RDF导入知识库"
    else
        info "写入知识到文件"
    fi
    echo "$knowledge" > "$DEPLOY_DIR/data/lpmm_raw_data/脚本单条知识.txt"
    info "激活虚拟环境"
    cd $DEPLOY_DIR && source $DEPLOY_venv/bin/activate 
    info "进行RDF实体提取"
    python3 ./scripts/info_extraction.py
    info "导入openie"
    python3 ./scripts/import_openie.py
}

# 显示菜单
show_menu() {
    clear
    print_title "MaiBot 管理面板 2025.11.09"

    echo -e "${CYAN}系统信息:${RESET}"
    echo -e "  用户: ${GREEN}$CURRENT_USER${RESET}"
    echo -e "  时间: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "  路径: ${GREEN}$DEPLOY_BASE${RESET}"
    echo ""

    echo -e "${CYAN}服务状态:${RESET}"
    echo -e "  MaiBot:                 $(check_service_status 'MaiBot' "$MAIBOT_PID_FILE")"
    echo -e "  MaiBot-Napcat-Adapter:  $(check_service_status 'MaiBot-Napcat-Adapter' "$ADAPTER_PID_FILE") TTS:$current_use_tts"
    echo ""

    free -h
    top -bn1 | grep "Cpu(s)" #| awk '{printf "CPU 使用率: %.2f%% (用户: %.2f%%, 系统: %.2f%%)\n",$2 + $4, $2, $4}'
    echo ""
      
    print_line
    echo -e "${BOLD}${YELLOW}操作菜单:${RESET}"
    print_line

    echo -e "  ${BOLD}${GREEN}[1]      ${RESET} 启动所有服务 (MaiBot + Adapter)"
    echo -e "  ${BOLD}${GREEN}[2]      ${RESET} 停止所有服务"
    echo ""
    echo -e "  ${BOLD}${GREEN}[3]      ${RESET} 仅启动 MaiBot"
    echo -e "  ${BOLD}${GREEN}[4/23]   ${RESET} 仅启动 MaiBot-Napcat-Adapter/切换适配器模式"
    echo ""
    echo -e "  ${BOLD}${GREEN}[5]      ${RESET} 仅停止 MaiBot"
    echo -e "  ${BOLD}${GREEN}[6]      ${RESET} 仅停止 MaiBot-Napcat-Adapter"
    echo ""
    echo -e "  ${BOLD}${GREEN}[7]      ${RESET} 前台启动 MaiBot"
    echo -e "  ${BOLD}${GREEN}[8]      ${RESET} 前台启动 MaiBot-Napcat-Adapter"
    echo ""
    echo -e "  ${BOLD}${GREEN}[9]      ${RESET} 查看 MaiBot 日志"
    echo -e "  ${BOLD}${GREEN}[10]     ${RESET} 查看 MaiBot-Napcat-Adapter 日志"
    echo ""
    echo -e "  ${BOLD}${GREEN}[11]     ${RESET} 清理 MaiBot 日志和PID"
    echo -e "  ${BOLD}${GREEN}[12]     ${RESET} 清理 MaiBot-Napcat-Adapter 日志和PID"
    echo ""
    echo -e "  ${BOLD}${GREEN}[13/14/19/22]  ${RESET} 安装/列出所有已安装的插件/更新插件/切换插件版本"
    echo -e "  ${BOLD}${GREEN}[15/20]        ${RESET} 更新麦麦/检查麦麦更新"
    echo -e "  ${BOLD}${GREEN}[16]           ${RESET} 更新脚本"
    echo -e "  ${BOLD}${GREEN}[17/21]        ${RESET} 导入openie/添加（一条）新的知识（执行RDF提取并导入）"
    echo -e "  ${BOLD}${GREEN}[18/24]        ${RESET} 安装（更新）依赖/pip list"
    echo ""
    echo -e "  ${BOLD}${GREEN}[0]  ${RESET} 退出脚本"

    print_line
    echo ""
    echo -ne "${BOLD}${YELLOW}请选择操作 [0-21]: ${RESET}"
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
    sleep 1
    local ada_config_file="$ADAPTER_DIR/config.toml"
    # 主循环
    while true; do
        current_use_tts=$(grep -E '^use_tts\s*=' "$ada_config_file" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
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
                cd $DEPLOY_DIR && source $DEPLOY_venv/bin/activate && python3 bot.py
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
				press_any_key
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
                cd $DEPLOY_DIR && source $DEPLOY_venv/bin/activate && python3 ./scripts/import_openie.py
                press_any_key 
                ;;
            18)
                echo -ne "${BOLD}${YELLOW}请输入包名："
                read Package_name
                info "激活虚拟环境"
                source "$DEPLOY_venv/bin/activate"
                info "开始安装$Package_name"
                if pip install $Package_name -i https://pypi.tuna.tsinghua.edu.cn/simple --upgrade; then
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
            20)
                if [ -d "$DEPLOY_DIR/.git" ]; then
                (
                    cd "$DEPLOY_DIR" || exit 1
                    echo -en "${BLUE}[INFO]${RESET} 正在连接到远程仓库......\r"
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
                                remote_info="${GREEN}麦麦已是最新版本${RESET}"
                            else
                                # 检查领先/落后情况
                                git fetch origin >/dev/null 2>&1
                                local ahead_behind=$(git rev-list --left-right --count HEAD...origin/HEAD 2>/dev/null)
                                if [ -n "$ahead_behind" ]; then
                                    local ahead=$(echo "$ahead_behind" | cut -f1)
                                    local behind=$(echo "$ahead_behind" | cut -f2)
                                    if [ "$behind" -gt 0 ]; then
                                        remote_info="${YELLOW}本地落后 $behind 个提交${RESET}"
                                    elif [ "$ahead" -gt 0 ]; then
                                        remote_info="${CYAN}远程领先 $ahead 个提交${RESET}"
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
                press_any_key
                ;;
            21)
                import_knowledge
                press_any_key
                ;;
            22)
                switch_plugin_version
                ;;
            23)
                switch_adapter_mode
                press_any_key
                ;;
            24)
                info "激活虚拟环境"
                source "$DEPLOY_venv/bin/activate"
                info "列出所有已安装的包..."
                if pip list; then
                    success "pip list 成功"
                else
                    warn "pip list 失败"
                fi
                info "列出所有可升级的包..."
                if pip list --outdate; then
                    success "pip list --outdate 成功"
                else
                    warn "pip list --outdate 失败"
                fi
                press_any_key
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
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main "$@"
