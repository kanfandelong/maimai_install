# MaiBot for Termux (PRoot)

在 Termux 的 PRoot 容器中部署 MaiBot 的自动化脚本

## 项目简介

本项目是基于 [Astriora/Antlia](https://github.com/Astriora/Antlia) 的 Linux 部署脚本修改而来，适配 Termux 环境的 PRoot 容器，让您能够在 Android 设备上部署并运行 MaiBot。

## 系统要求

- Android 5.0 或更高版本
- 稳定的网络连接
- 至少 5GB 可用存储空间

## 快速开始

### 1. 更新 Termux
```bash
pkg upgrade
```

### 2. 安装 PRoot 环境
```bash
awk -f <(curl -L l.tmoe.me/2.awk)
```
按照提示选择安装 Ubuntu 系统

### 3. 安装必要工具
在 PRoot 的 Ubuntu 环境中执行：
```bash
sudo apt install wget
```

### 4. 下载并运行安装脚本
```bash
wget -O MaiBot-install.sh https://github.com/kanfandelong/maimai_install/raw/main/MaiBot-install.sh && bash MaiBot-install.sh
```

### 5. 更新 Shell 环境（首次安装后需要）
```bash
source ~/.bashrc
```

### 6. 启动 MaiBot
```bash
maibot
```

## 功能特点

- ✅ tmoe自动配置 PRoot 环境
- ✅ 一键安装 MaiBot 及其依赖
- ✅ 简单的启动命令

## 注意事项

- 首次运行 `maibot` 命令前必须执行 `source ~/.bashrc`
- 确保设备有足够的电量和存储空间
- 建议在稳定的 Wi-Fi 环境下进行安装

## 故障排除

如果遇到问题，请尝试：

1. 重新启动 Termux
2. 使用tmoe停止容器进程
3. 检查网络连接
4. 向作者反馈

## 致谢

- 感谢 [Astriora/Antlia](https://github.com/Astriora/Antlia) 项目原始linux部署脚本
- 感谢所有贡献者和测试者

## 许可证

本项目基于原项目的许可证，具体请参考原仓库的许可证信息。
