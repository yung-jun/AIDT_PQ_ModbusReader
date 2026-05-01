#!/bin/bash

###############################################################################
# AIDT PQ Modbus Reader - Raspberry Pi 自動安裝腳本
# 
# 此腳本會自動完成以下任務:
# 1. 更新系統
# 2. 安裝必要的軟體
# 3. 設定 Python 虛擬環境
# 4. 安裝 Python 依賴
# 5. 配置串口權限
# 6. 創建必要的目錄
#
# 使用方法:
#   chmod +x setup_raspberry_pi.sh
#   ./setup_raspberry_pi.sh
###############################################################################

set -e  # 遇到錯誤立即退出

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日誌函數
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查是否為 root 用戶
if [ "$EUID" -eq 0 ]; then 
    log_error "請不要使用 root 用戶執行此腳本"
    exit 1
fi

log_info "開始安裝 AIDT PQ Modbus Reader..."

# 1. 更新系統
log_info "更新系統套件..."
sudo apt update
sudo apt upgrade -y

# 2. 安裝必要的軟體
log_info "安裝必要的軟體..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    htop \
    logrotate \
    minicom

# 3. 設定串口權限
log_info "設定串口權限..."
sudo usermod -a -G dialout $USER
log_warn "串口權限已設定，需要重新登入才能生效"

# 4. 獲取專案路徑
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info "專案目錄: $PROJECT_DIR"

# 5. 創建 Python 虛擬環境
log_info "創建 Python 虛擬環境..."
cd "$PROJECT_DIR"

if [ -d "venv" ]; then
    log_warn "虛擬環境已存在，跳過創建"
else
    python3 -m venv venv
    log_info "虛擬環境創建完成"
fi

# 6. 啟動虛擬環境並安裝依賴
log_info "安裝 Python 依賴..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 7. 創建必要的目錄
log_info "創建數據目錄..."
mkdir -p data/csv
mkdir -p logger

# 8. 檢查串口設備
log_info "檢查串口設備..."
if ls /dev/ttyUSB* 1> /dev/null 2>&1; then
    log_info "找到串口設備:"
    ls -l /dev/ttyUSB*
else
    log_warn "未找到 /dev/ttyUSB* 設備，請確認 USB to RS-485 轉換器已連接"
fi

# 9. 創建配置檔案備份
if [ -f "config.json" ]; then
    log_info "備份現有配置檔案..."
    cp config.json config.json.backup.$(date +%Y%m%d_%H%M%S)
fi

# 10. 提示用戶編輯配置
log_info "安裝完成！"
echo ""
log_warn "下一步操作:"
echo "  1. 編輯 config.json，將 serial_port 改為 /dev/ttyUSB0"
echo "  2. 重新登入以使串口權限生效: logout 或 exit"
echo "  3. 測試運行: cd $PROJECT_DIR && source venv/bin/activate && python run.py"
echo "  4. 設定自動啟動: sudo cp scripts/modbus-reader.service /etc/systemd/system/"
echo ""

deactivate
