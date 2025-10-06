#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_CONFIG_FILE="$SCRIPT_DIR/path.conf"
PLUGINS_LIST_FILE="$SCRIPT_DIR/plugins.list"
BACKUP_DIR="$SCRIPT_DIR/backups"

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
}

press_any_key() {
    echo -ne "${BOLD}${YELLOW}按任意键继续...${RESET}"
    read -n 1 -s
    echo
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
                success "已选择: ghfast.top 镜像 (默认)"
                break
                ;;
        esac
    done
}

download_with_retry() {
    local url="$1"
    local target="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if wget -O "$target" "$url" 2>/dev/null || curl -sL -o "$target" "$url"; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        warn "下载失败，重试 $retry_count/$max_retries..."
        sleep 2
    done
    error "下载失败: $url"
    return 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "未找到命令: $1，请先安装"
        return 1
    fi
    return 0
}

backup_plugin() {
    local plugin_name="$1"
    local backup_file="$BACKUP_DIR/${plugin_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if [ -d "$PLUGIN_DIR/$plugin_name" ]; then
        info "备份插件: $plugin_name"
        tar -czf "$backup_file" -C "$PLUGIN_DIR" "$plugin_name" 2>/dev/null
        if [ $? -eq 0 ]; then
            success "插件已备份到: $backup_file"
        else
            warn "插件备份失败"
        fi
    fi
}

show_plugin_info() {
    local plugin_name="$1"
    local plugin_dir="$PLUGIN_DIR/$plugin_name"
    
    if [ ! -d "$plugin_dir" ]; then
        error "插件不存在: $plugin_name"
        return 1
    fi
    
    print_title "插件信息: $plugin_name"
    
    # 显示 config.toml
    if [ -f "$plugin_dir/config.toml" ]; then
        echo -e "${BOLD}${GREEN}配置信息:${RESET}"
        head -20 "$plugin_dir/config.toml"
        echo
	else
		echo -e "   ${YELLOW}⚠ 无配置文件，请重启MaiBot以生成配置文件${RESET}"
    fi
    
    # 显示 README
    read -p "你要查看插件的 README 吗 (y/n, 默认y): " del_choice # 询问用户是否删除
    del_choice=${del_choice:-y} # 默认选择不删除
    if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then 
        if [ -f "$plugin_dir/README.md" ]; then
            echo -e "${BOLD}${GREEN}README:${RESET}"
            if command -v bat &> /dev/null; then
                bat -p "$plugin_dir/README.md" 2>/dev/null || head -50 "$plugin_dir/README.md"
            else
                head -50 "$plugin_dir/README.md"
            fi
        elif [ -f "$plugin_dir/README" ]; then
            echo -e "${BOLD}${GREEN}README:${RESET}"
            head -50 "$plugin_dir/README"
        else
            warn "未找到 README 文件"
        fi
    fi
}

install_plugins() {
    echo -ne "${BOLD}${YELLOW}请输入插件仓库地址 : ${RESET}"
    read -r plugin_url_input
    
    if [ -z "$plugin_url_input" ]; then
        warn "输入为空，取消操作"
        return
    fi
    
    plugin_name=$(basename "$plugin_url" .git)
    
    # 检查是否已安装
    if [ -d "$PLUGIN_DIR/$plugin_name" ]; then
        warn "检测到插件 $plugin_name 已存在"
        echo "1) 重新安装 (删除后重新克隆)"
        echo "2) 更新插件"
        echo "3) 跳过"
        echo -ne "请选择 [1-3, 默认3]: "
        read -r choice
        
        case "${choice:-3}" in
            1)
                backup_plugin "$plugin_name"
                rm -rf "$PLUGIN_DIR/$plugin_name"
                success "已删除旧版本插件"
                ;;
            2)
                update_single_plugin "$plugin_name"
                return
                ;;
            *)
                warn "已跳过插件安装"
                return
                ;;
        esac
    fi
    
    select_github_proxy
    
    info "开始克隆插件: $plugin_name"
    if git clone --depth 1 "${GITHUB_PROXY}$plugin_url" "$PLUGIN_DIR/$plugin_name" 2>/dev/null; then
        success "插件克隆成功"
    else
        error "插件克隆失败"
        press_any_key
        return
    fi
    
    # 安装依赖
    if [ -f "$PLUGIN_DIR/$plugin_name/requirements.txt" ]; then
        info "安装插件依赖..."
        source "$DEPLOY_DIR/.venv/bin/activate"
        
        if pip install -r "$PLUGIN_DIR/$plugin_name/requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple; then
            success "依赖安装成功"
            # 记录到插件列表
            echo "$plugin_url $(date '+%Y-%m-%d %H:%M:%S')" >> "$PLUGINS_LIST_FILE"
        else
            warn "依赖安装失败，但插件文件已下载"
        fi
        deactivate
    else
        warn "未找到 requirements.txt，跳过依赖安装"
        echo "$plugin_url $(date '+%Y-%m-%d %H:%M:%S')" >> "$PLUGINS_LIST_FILE"
    fi
    
    # 显示插件信息
    show_plugin_info "$plugin_name"
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
                cd "$plugin" || continue
                local git_url=$(git remote get-url origin 2>/dev/null || echo "未知")
                local git_branch=$(git branch --show-current 2>/dev/null || echo "未知")
                local git_commit=$(git log -1 --format="%h %ad" --date=short 2>/dev/null || echo "未知")
                cd - >/dev/null || continue
                
                echo -e "   ${BLUE}仓库:${RESET} $git_url"
                echo -e "   ${BLUE}分支:${RESET} $git_branch"
                echo -e "   ${BLUE}最新提交:${RESET} $git_commit"
            fi
            
            # 检查配置文件
            if [ -f "$plugin/config.toml" ]; then
                echo -e "   ${GREEN}✓ 包含配置文件${RESET}"
            else
                echo -e "   ${YELLOW}⚠ 无配置文件，请重启MaiBot${RESET}"
            fi
            
            echo
        fi
    done
    echo -e "${BOLD}总计: $count 个插件${RESET}"
}

update_single_plugin() {
    local plugin_name="$1"
    local plugin_dir="$PLUGIN_DIR/$plugin_name"
    
    if [ ! -d "$plugin_dir" ]; then
        error "插件不存在: $plugin_name"
        return 1
    fi
    
    if [ ! -d "$plugin_dir/.git" ]; then
        warn "插件 $plugin_name 不是 git 仓库，无法更新"
        return 1
    fi
    
    cd "$plugin_dir" || return 1
    
    # 备份当前更改
    if ! git diff --quiet; then
        warn "插件有未提交的更改，正在备份..."
        backup_plugin "$plugin_name"
    fi
    
	info "开始更新插件: $plugin_name"
    if git pull; then
        success "插件更新成功"
        
        # 更新依赖
        if [ -f "requirements.txt" ]; then
            info "更新依赖..."
            source "$DEPLOY_DIR/.venv/bin/activate"
            pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
            deactivate
        fi
    else
        error "插件更新失败"
    fi
    
    cd - >/dev/null || return 1
}

update_all_plugins() {
    print_title "更新所有插件"
    
    if [ ! -d "$PLUGIN_DIR" ] || [ -z "$(ls -A "$PLUGIN_DIR")" ]; then
        warn "未安装任何插件"
        return
    fi
    
    local updated=0
    local failed=0
    
    for plugin in "$PLUGIN_DIR"/*; do
        if [ -d "$plugin" ] && [ -d "$plugin/.git" ]; then
            plugin_name=$(basename "$plugin")
            if update_single_plugin "$plugin_name"; then
                updated=$((updated + 1))
            else
                failed=$((failed + 1))
            fi
            echo
        fi
    done
    
    print_line
    if [ $updated -gt 0 ]; then
        success "成功更新 $updated 个插件"
    fi
    if [ $failed -gt 0 ]; then
        error "$failed 个插件更新失败"
    fi
    if [ $updated -eq 0 ] && [ $failed -eq 0 ]; then
        info "没有需要更新的插件"
    fi
}

uninstall_plugin() {
    list_plugins
    echo
    echo -ne "${BOLD}${YELLOW}请输入要卸载的插件名称: ${RESET}"
    read -r plugin_name
    
    if [ -z "$plugin_name" ]; then
        warn "输入为空，取消操作"
        return
    fi
    
    if [ ! -d "$PLUGIN_DIR/$plugin_name" ]; then
        error "插件不存在: $plugin_name"
        press_any_key
        return
    fi
    
    warn "即将卸载插件: $plugin_name"
    echo -e "${RED}此操作将删除插件目录及其所有文件！${RESET}"
    echo -ne "确认卸载？(y/N): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        backup_plugin "$plugin_name"
        rm -rf "$PLUGIN_DIR/$plugin_name"
        success "插件 $plugin_name 已卸载"
    else
        info "取消卸载"
    fi
    press_any_key
}

plugin_manager_info() {
    print_title "插件管理器信息"
    
    echo -e "${BOLD}${GREEN}路径信息:${RESET}"
    echo -e "  脚本目录: $SCRIPT_DIR"
    echo -e "  部署目录: $DEPLOY_DIR"
    echo -e "  插件目录: $PLUGIN_DIR"
    echo -e "  备份目录: $BACKUP_DIR"
    echo
    
    # 统计信息
    local total_plugins=0
    local with_config=0
    local git_repos=0
    
    if [ -d "$PLUGIN_DIR" ]; then
        for plugin in "$PLUGIN_DIR"/*; do
            if [ -d "$plugin" ]; then
                total_plugins=$((total_plugins + 1))
                [ -f "$plugin/config.toml" ] && with_config=$((with_config + 1))
                [ -d "$plugin/.git" ] && git_repos=$((git_repos + 1))
            fi
        done
    fi
    
    echo -e "${BOLD}${GREEN}统计信息:${RESET}"
    echo -e "  总插件数: $total_plugins"
    echo -e "  含配置插件: $with_config"
    echo -e "  Git 仓库: $git_repos"
    echo
    
    # 备份信息
    if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${BOLD}${GREEN}备份文件:${RESET}"
        ls -lh "$BACKUP_DIR" | head -10
    fi
}

install_plugins() {
	echo -ne "${BOLD}${YELLOW}请输入插件仓库地址："
	read plugin_url
	plugin_name=$(basename "$plugin_url" .git)
	select_github_proxy
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
    git clone --depth 1 "${GITHUB_PROXY}$plugin_url" "$PLUGIN_DIR/$plugin_name" # 克隆仓库
	
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

show_menu() {
    clear
    print_title "MaiBot 插件管理器 $(date '+%Y.%m.%d')"
    
    echo -e "${BOLD}${YELLOW}操作菜单:${RESET}"
    print_line
    echo ""
    echo -e "  ${BOLD}${GREEN}[1]${RESET}  安装插件"
    echo -e "  ${BOLD}${GREEN}[2]${RESET}  列出插件"
    echo -e "  ${BOLD}${GREEN}[3]${RESET}  更新所有插件"
    echo -e "  ${BOLD}${GREEN}[4]${RESET}  更新单个插件"
    echo -e "  ${BOLD}${GREEN}[5]${RESET}  卸载插件"
    echo -e "  ${BOLD}${GREEN}[6]${RESET}  插件信息"
    echo -e "  ${BOLD}${GREEN}[7]${RESET}  管理器信息"
    echo ""
    echo -e "  ${BOLD}${GREEN}[8]${RESET}  更新脚本"
    echo -e "  ${BOLD}${GREEN}[9]${RESET}  重新初始化路径"
    echo ""
    echo -e "  ${BOLD}${GREEN}[0]${RESET}  退出脚本"
    
    print_line
    echo -e "${BOLD}${CYAN}当前用户:${RESET} $(whoami)"
    echo -e "${BOLD}${CYAN}插件目录:${RESET} $PLUGIN_DIR"
    print_line
    echo ""
    echo -ne "${BOLD}${YELLOW}请选择操作 [0-9]: ${RESET}"
}

# =============================================================================
# 主程序
# =============================================================================
main() {
    # 检查必要命令
    check_command git || exit 1
    check_command pip || exit 1
    
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
        read -r choice
        
        case $choice in
            1) install_plugins ;;
            2) list_plugins; press_any_key ;;
            3) update_all_plugins; press_any_key ;;
            4) 
                echo -ne "请输入插件名称: "
                read -r plugin_name
                update_single_plugin "$plugin_name"
                press_any_key 
                ;;
            5) uninstall_plugin ;;
            6) 
                echo -ne "请输入插件名称: "
                read -r plugin_name
                show_plugin_info "$plugin_name"
                press_any_key 
                ;;
            7) plugin_manager_info; press_any_key ;;
            8)
                local DOWNLOAD_URL="${GITHUB_PROXY}https://github.com/kanfandelong/maimai_install/raw/main/Plugin_Manager.sh"
                local TARGET_FILE="$SCRIPT_DIR/Plugin_Manager.sh"
                select_github_proxy
                if download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE"; then
                    chmod +x "$TARGET_FILE"
                    success "脚本更新成功"
                else
                    error "脚本更新失败"
                fi
				chmod +x "$TARGET_FILE" || err "无法设置执行权限: $TARGET_FILE"
                press_any_key
                ;;
            9)
                rm -f "$PATH_CONFIG_FILE"
                init_paths
                success "路径已重新初始化"
                press_any_key
                ;;
            114514) 
                echo "本脚本仓库地址: https://github.com/kanfandelong/maimai_install" 
                press_any_key  
                ;;
            0)
                echo -e "${GREEN}感谢使用！${RESET}"
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