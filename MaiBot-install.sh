#!/bin/bash

# 获取脚本绝对路径
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # 获取脚本所在目录
DEPLOY_DIR="$SCRIPT_DIR" # 部署目录
LOG_FILE="$SCRIPT_DIR/script.log" #  日志文件路径
DEPLOY_STATUS_FILE="$SCRIPT_DIR/MaiBot/deploy.status" # 部署状态文件
LOCAL_BIN="$HOME/.local/bin" 
MAIBOT_BIN="$LOCAL_BIN/maibot"

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1 # 检查命令是否存在
}

# =============================================================================
# 日志函数
# =============================================================================
# 定义颜色
RESET='\033[0m'     # 重置颜色
BOLD='\033[1m'      # 加粗
RED='\033[31m'      # 红色
GREEN='\033[32m'    # 绿色
YELLOW='\033[33m'   # 黄色
BLUE='\033[34m'     # 蓝色
CYAN='\033[36m'     # 青色

# 信息日志
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }

# 成功日志
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }

# 警告日志
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# 错误日志
err() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

# 打印标题
print_title() { echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"; }

download_with_retry() {                                   #定义函数
    local url="$1"                                        #获取参数
    local output="$2"                                     #获取参数
    local max_attempts=3                                  #最大尝试次数
    local attempt=1                                       #当前尝试次数

    while [[ $attempt -le $max_attempts ]]; do            #循环直到达到最大尝试次数
        info "下载尝试 $attempt/$max_attempts: $url"       #打印信息日志
        if command_exists wget; then                      #如果 wget 存在
            if wget -O "$output" "$url" 2>/dev/null; then #使用 wget 下载
                ok "下载成功: $output"                     #打印日志
                return 0                                  #成功返回
            fi                                            #结束条件判断
        elif command_exists curl; then                    #如果 curl 存在
            if curl -L -o "$output" "$url" 2>/dev/null; then #使用 curl 下载
                ok "下载成功: $output"                         #打印日志
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
    err "所有下载尝试都失败了"                                   #打印错误日志并退出
}                                                             #结束函数定义

select_github_proxy() {                                               #定义函数
    print_title "选择 GitHub 代理"                                     #打印标题
    echo "请根据您的网络环境选择一个合适的下载代理："                        #打印提示
    echo                                                             #打印空行

    # 使用 select 提供选项
    select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
        case $proxy_choice in
            "ghfast.top 镜像 (推荐)") 
                GITHUB_PROXY="https://ghfast.top/"; 
                ok "已选择: ghfast.top 镜像" 
                break
                ;;
            "ghproxy.net 镜像") 
                GITHUB_PROXY="https://ghproxy.net/"; 
                ok "已选择: ghproxy.net 镜像" 
                break
                ;;
            "不使用代理") 
                GITHUB_PROXY=""; 
                ok "已选择: 不使用代理" 
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
                ok "已选择: 自定义代理 - $GITHUB_PROXY"
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
} #结束函数定义    


check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        # 已经是root，不需要sudo
        SUDO=""
        ok "当前是 root 用户"
    elif command_exists sudo; then
        # 有sudo命令
        SUDO="sudo"
        ok "检测到 sudo 命令"
    else
        # 没有sudo
        SUDO=""
        warn "系统没有 sudo "
    fi
}


# =============================================================================
# 系统检测
# =============================================================================
detect_system() {                               #定义函数
    print_title "检测系统环境"                     #打印标题
    ID="${ID:-}"
    # 检测架构
    ARCH=$(uname -m)                          #获取系统架构
    case $ARCH in # 根据架构打印信息
        x86_64|aarch64|arm64) 
            ok "系统架构: $ARCH (支持)"  #打印信息
            ;;
        *) 
            warn "架构 $ARCH 可能不被完全支持，继续尝试..."  #打印警告
            ;;
    esac
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then  #如果文件存在
        source /etc/os-release #加载文件
        ok "检测到系统: $NAME" #打印信息
    else  # 否则
        warn "无法检测具体系统版本" #打印警告 
    fi   #结束条件判断
    
    # 检测包管理器
    check_sudo
    detect_package_manager
}                           #结束函数定义


# =============================================================================
# 包管理器检测
# =============================================================================
detect_package_manager() {                          #定义函数
    info "检测包管理器..."                     #打印信息日志
    
    local managers=(                   #定义包管理器数组
        "apt:Debian/Ubuntu"    
        "pacman:Arch Linux"
        "dnf:Fedora/RHEL/CentOS"
        "yum:RHEL/CentOS (老版本)"
        "zypper:openSUSE"
        "apk:Alpine Linux"
        "brew:macOS/Linux (Homebrew)"
    ) #结束数组定义
    
    for manager_info in "${managers[@]}"; do  #循环遍历数组
        local manager="${manager_info%%:*}"  #提取包管理器名称
        local distro="${manager_info##*:}"   #提取发行版名称
        
        if command_exists "$manager"; then   #如果包管理器存在
            PKG_MANAGER="$manager"           #设置全局变量
            DISTRO="$distro"                 #设置全局变量
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)" #打印信息日志
            return 0                          #成功返回
        fi                                    #结束条件判断
    done                                   #结束循环
    
    err "未检测到支持的包管理器，请手动安装 git、curl/wget 和 python3" #打印错误日志并退出
}                                          #结束函数定义

install_package() { #定义函数
    local package="$1"                           #获取参数
    
    info "安装 $package..."                  #打印信息日志
    case $PKG_MANAGER in                   #根据包管理器选择安装命令
        pacman)
            $SUDO pacman -S --noconfirm "$package" #安装包
            ;;
        apt)
            $SUDO apt update -qq 2>/dev/null || true #更新包列表
            $SUDO apt install -y "$package"          #安装包
            ;;
        dnf)
            # 如果是安装 screen，先确保 EPEL 已启用
            if [[ "$package" == "screen" ]]; then
                if ! dnf repolist enabled | grep -q epel; then
                    info "启用 EPEL 仓库以安装 screen..."
                    $SUDO dnf install -y epel-release 2>/dev/null || true
                fi
            fi
            $SUDO dnf install -y "$package"   #安装包
            ;;
        yum)
            # 如果是安装 screen，先确保 EPEL 已启用
            if [[ "$package" == "screen" ]]; then
                if ! yum repolist enabled | grep -q epel; then
                    info "启用 EPEL 仓库以安装 screen..."
                    $SUDO yum install -y epel-release 2>/dev/null || true
                fi
            fi
            $SUDO yum install -y "$package"  #安装包
            ;;
        zypper)
            $SUDO zypper install -y "$package" #安装包
            ;;
        apk)
            $SUDO apk add gcc musl-dev linux-headers "$package" #安装包
            ;;
        brew)
            $SUDO install "$package" #安装包
            ;;
        *)
            warn "未知包管理器 $PKG_MANAGER，请手动安装 $package" #打印警告
            ;;
    esac #结束条件判断
} #结束函数定义

#------------------------------------------------------------------------------
# 安装对应 Python 版本的 venv
install_venv_package() {
    info "检查并安装 Python venv 模块..."
    
    # 获取 Python 主次版本号（如 3.12）
    python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    info "当前系统 Python 版本: $python_version"
    
    # 检查系统类型
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                info "当前系统为 Ubuntu/Debian"
                venv_package="python$python_version-venv"
                
                # 检查是否已安装
                if dpkg -l | grep -q "$venv_package"; then
                    ok "已安装 $venv_package"
                else
                    info "安装 $venv_package..."
                    sudo apt update && sudo apt install -y "$venv_package"
                    if [[ $? -eq 0 ]]; then
                        ok "成功安装 $venv_package"
                    else
                        err "安装 $venv_package 失败"
                        return 1
                    fi
                fi
                ;;
            centos|rhel|fedora)
                info "当前系统为 CentOS/RHEL/Fedora"
                # 在 RHEL/CentOS/Fedora 上，venv 通常包含在 python3 包中
                if ! python3 -c "import venv" 2>/dev/null; then
                    info "安装 python3-venv 或类似包..."
                    if command -v dnf >/dev/null 2>&1; then
                        sudo dnf install -y "python$python_version-tools" || sudo dnf install -y python3-venv
                    elif command -v yum >/dev/null 2>&1; then
                        sudo yum install -y "python$python_version-tools" || sudo yum install -y python3-venv
                    fi
                else
                    ok "Python venv 模块已可用"
                fi
                ;;
            arch|manjaro)
                info "检测到 Arch/Manjaro 系统"
                # Arch Linux 通常已经包含了 venv
                if ! python3 -c "import venv" 2>/dev/null; then
                    warn "请手动安装 Python venv: sudo pacman -S python"
                else
                    ok "Python venv 模块已可用"
                fi
                ;;
            *)
                warn "未知系统 $ID，尝试使用系统 Python venv"
                if ! python3 -c "import venv" 2>/dev/null; then
                    err "无法找到 venv 模块，请手动安装"
                    return 1
                fi
                ;;
        esac
    else
        warn "无法检测系统类型，尝试使用系统 Python venv"
        if ! python3 -c "import venv" 2>/dev/null; then
            err "无法找到 venv 模块，请手动安装"
            return 1
        fi
    fi
    
    ok "Python venv 环境就绪"
    return 0
}

# =============================================================================
# 系统依赖安装
# =============================================================================
install_system_dependencies() {   #定义函数
    print_title "安装系统依赖"  #打印标题
    
    local packages=("git" "python3" "tar" "findutils" "zip")  #定义必需包数组 "screen"
    
    # 检查下载工具
    if ! command_exists curl && ! command_exists wget; then  #如果 curl 和 wget 都不存在
        packages+=("curl")   #添加 curl 到数组
    fi                                  #结束条件判断
    
	#在termux中，使用pip和原始的venv管理依赖环境，uv在termux中无法很好的运行
    # Arch 系统特殊处理：添加 uv 到必需包数组
    # if [[ "$ID" == "arch" ]]; then
        # 只有 Arch 才用包管理器安装 uv
        # packages+=("uv")
        # info "已将 uv 添加到 Arch 的必需安装包列表"
    #fi
    if ! command_exists pip3 && ! command_exists pip; then   #如果 pip3 和 pip 都不存在
        case $PKG_MANAGER in                                 #根据包管理器选择 pip 包名称
            apt) packages+=("python3-pip") ;;                # apt
            pacman) packages+=("python-pip") ;;              # pacman
            dnf|yum) packages+=("python3-pip") ;;            # dnf 和 yum
            zypper) packages+=("python3-pip") ;;             # zypper
            apk) packages+=("py3-pip") ;;                    # apk
            brew) packages+=("pip3") ;;                      # brew
            *) packages+=("python3-pip") ;;                  #默认
        esac                                                 #结束条件判断
    fi
    # 检查 gcc/g++ 是否存在，如果都不存在则安装
    if ! command_exists gcc || ! command_exists g++; then
     case $PKG_MANAGER in
        apt)
            packages+=("build-essential")      # 包含 gcc g++ make 等
            ;;
        pacman)
            packages+=("base-devel")           # Arch 基础开发包，包含 gcc g++
            ;;
        dnf|yum)
            packages+=("gcc" "gcc-c++" "make")
            ;;
        zypper)
            packages+=("gcc" "gcc-c++" "make")
            ;;
        apk)
            packages+=("build-base")           # Alpine 包含 gcc g++ make
            ;;
        brew)
            packages+=("gcc")
            ;;
        *)
            echo "未知包管理器，请手动安装 gcc/g++"
            ;;
      esac
    fi


    info "安装必需的系统包..."                                 #打印信息日志
    for package in "${packages[@]}"; do                     #循环遍历包数组
        if command_exists "${package/python3-pip/pip3}"; then #如果包已安装
            ok "$package 已安装"                               #打印信息日志
        else                                                  #否则
            install_package "$package"                        #安装包
        fi                                                    #结束条件判断
    done                                                      #结束循环
    
	#检查venv
	install_venv_package
	
    ok "系统依赖安装完成"  #打印成功日志
}                          #结束函数定义

clone_maibot() {
            local CLONE_URL="${GITHUB_PROXY}https://github.com/MaiM-with-u/MaiBot.git" # 选择官方源
            local CLONE_URL1="${GITHUB_PROXY}https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"

    if [ -d "$DEPLOY_DIR/MaiBot" ]; then # 如果目录已存在
        warn "检测到MaiBot 文件夹已存在。是否删除并重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MaiBot" # 删除MaiBot目录
            ok "已删除MaiBot 文件夹。" # 提示用户已删除
        else # 如果用户选择不删除
            warn "跳过MaiBot仓库克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
    info "克隆 MaiBot 仓库" # 提示用户开始克隆
    git clone --depth 1 "$CLONE_URL" # 克隆仓库
    
    if [ -d "$DEPLOY_DIR/MaiBot-Napcat-Adapter" ]; then # 如果目录已存在
        warn "检测到MaiBot-Napcat-Adapter文件夹已存在。是否删除并重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MaiBot-Napcat-Adapter" # 删除目录
            ok "已删除MaiBot-Napcat-Adapter文件夹。" # 提示用户已删除
        else # 如果用户选择不删除
            warn "跳过MaiBot-Napcat-Adapter仓库克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
     git clone --depth 1 "$CLONE_URL1" # 克隆仓库
}  # 克隆 仓库结束

# 安装 Python 依赖
install_python_dependencies() {
    print_title "安装 Python 依赖"

    local original_dir="$PWD"

    # 安装 MaiBot 依赖
    cd "$DEPLOY_DIR/MaiBot" || err "无法进入 MaiBot 目录"
    info "安装 MaiBot 依赖..."
    
    # 创建并激活虚拟环境
    if [ ! -d ".venv" ]; then
        python3 -m venv .venv || err "虚拟环境创建失败"
    fi
    
    if [ -f ".venv/bin/activate" ]; then
        source .venv/bin/activate
    else
        err "虚拟环境激活失败：.venv/bin/activate 不存在"
    fi
    
    # 升级 pip
    pip install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple || warn "pip 升级失败，继续安装..."
    
    attempt=1
    while [[ $attempt -le 3 ]]; do
        if [[ -f "requirements.txt" ]]; then
            if pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple; then
                ok "MaiBot 依赖安装成功"
                break
            else
                warn "MaiBot 依赖安装失败,重试 $attempt/3"
                ((attempt++))
                sleep 5
            fi
        else
            err "未找到 requirements.txt 文件"
        fi
    done
    
    if [[ $attempt -gt 3 ]]; then
        err "MaiBot 依赖安装多次失败"
    fi
   
    info "MaiBot 配置文件初始化..."
    mkdir -p config || warn "创建 config 目录失败"
    
    # 复制配置文件
    [[ -f "template/bot_config_template.toml" ]] && cp "template/bot_config_template.toml" "config/bot_config.toml"
    [[ -f "template/model_config_template.toml" ]] && cp "template/model_config_template.toml" "config/model_config.toml"
    [[ -f "template/template.env" ]] && cp "template/template.env" ".env"
    
    ok "MaiBot 配置初始化完成"

    # 安装 Napcat Adapter 依赖
    cd "$DEPLOY_DIR/MaiBot-Napcat-Adapter" || err "无法进入 Adapter 目录"
    info "安装 Napcat Adapter 依赖..."
    
    # 使用 MaiBot 的虚拟环境
    source "$DEPLOY_DIR/MaiBot/.venv/bin/activate"
    
    if [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple || warn "Adapter 依赖安装失败"
    else
        warn "未找到 Adapter 的 requirements.txt 文件"
    fi

    # 复制 Adapter 配置文件
    [[ -f "template/template_config.toml" ]] && cp "template/template_config.toml" "config.toml"
    
    # 退出虚拟环境并返回原目录
    deactivate
    cd "$original_dir"
    
    ok "Python 依赖安装完成"
}

update_shell_config() {
    local path_export='export PATH="$HOME/.local/bin:$PATH"'  # 修正路径
    local fish_path_set='set -gx PATH "$HOME/.local/bin" $PATH'  # 修正路径

    # 检查并更新 shell 配置
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -qF "$path_export" "$HOME/.bashrc"; then
            echo "$path_export" >> "$HOME/.bashrc"
            ok "已更新 .bashrc"
        fi
    fi
    
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -qF "$path_export" "$HOME/.zshrc"; then
            echo "$path_export" >> "$HOME/.zshrc"
            ok "已更新 .zshrc"
        fi
    fi
    
    local fish_config="$HOME/.config/fish/config.fish"
    if mkdir -p "$(dirname "$fish_config")" && [[ -f "$fish_config" ]]; then
        if ! grep -qF "$fish_path_set" "$fish_config"; then
            echo "$fish_path_set" >> "$fish_config"
            ok "已更新 fish 配置"
        fi
    fi
}


download-script() {
    local DOWNLOAD_URL="${GITHUB_PROXY}https://github.com/kanfandelong/maimai_install/raw/main/maibot.sh"
    local TARGET_DIR="$LOCAL_BIN"
    local TARGET_FILE="$TARGET_DIR/maibot"  # 修正文件路径

    mkdir -p "$TARGET_DIR" || warn "无法创建目录 $TARGET_DIR，尝试使用当前权限继续"

    # 下载 maibot 脚本
    download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE"
    chmod +x "$TARGET_FILE" || err "无法设置执行权限: $TARGET_FILE"
    ok "maibot 启动脚本已下载到 $TARGET_FILE"

    # maibot 初始化
    if [[ -f "$TARGET_FILE" ]]; then
        "$TARGET_FILE" --init="$SCRIPT_DIR" || warn "maibot 初始化可能有问题，请检查"
        ok "maibot 已初始化到 $SCRIPT_DIR"
    else
        err "maibot 脚本下载失败，初始化中止"
    fi

    echo "Downloaded at $(date)" > "$TARGET_DIR/maibot_download.log"
}






main() {
    print_title "MaiBot 自动部署脚本"
	print_title "看番の龙二次修改版本"
	print_title "适用于termux的proot容器环境"
    detect_system

    # 选择 GitHub 代理
    select_github_proxy

    # 安装系统依赖
    install_system_dependencies

    # 克隆仓库
    clone_maibot

    # 安装 Python 依赖
    install_python_dependencies

    # 更新 shell 配置
    update_shell_config

    # 下载 maibot 脚本
    TARGET_PATH="$LOCAL_BIN/maibot"
    download-script

    ok "MaiBot 部署完成！ 执行: 
    source  ~/.bashrc # 初次启动时需要重新加载.bashrc以使别名生效
    maibot
    来启动"
}

# 执行主函数
main
