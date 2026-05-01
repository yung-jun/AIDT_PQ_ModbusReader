#!/bin/bash

###############################################################################
# AIDT PQ Modbus Reader - 系統診斷腳本
# 
# 此腳本會收集系統資訊，幫助診斷問題
#
# 使用方法:
#   chmod +x diagnose.sh
#   ./diagnose.sh
#   ./diagnose.sh > diagnostic_report.txt  # 儲存到檔案
###############################################################################

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 標題函數
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_section() {
    echo -e "${GREEN}>>> $1${NC}"
    echo ""
}

print_warning() {
    echo -e "${YELLOW}[警告] $1${NC}"
}

print_error() {
    echo -e "${RED}[錯誤] $1${NC}"
}

# 獲取專案路徑
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_header "AIDT PQ Modbus Reader - 系統診斷報告"
echo "生成時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo "專案目錄: $PROJECT_DIR"
echo ""

# 1. 系統資訊
print_section "1. 系統資訊"
echo "作業系統:"
cat /etc/os-release | grep PRETTY_NAME
echo ""
echo "核心版本:"
uname -r
echo ""
echo "硬體型號:"
cat /proc/device-tree/model 2>/dev/null || echo "無法獲取"
echo ""
echo "系統運行時間:"
uptime
echo ""

# 2. 硬體資源
print_section "2. 硬體資源"

echo "CPU 資訊:"
lscpu | grep "Model name\|Architecture\|CPU(s):"
echo ""

echo "CPU 溫度:"
TEMP=$(vcgencmd measure_temp 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "$TEMP"
    TEMP_VALUE=$(echo $TEMP | sed 's/temp=//' | sed "s/'C//" | cut -d. -f1)
    if [ $TEMP_VALUE -gt 70 ]; then
        print_warning "CPU 溫度過高！建議安裝散熱片或風扇"
    fi
else
    echo "無法獲取 CPU 溫度"
fi
echo ""

echo "記憶體使用:"
free -h
MEMORY_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
echo "記憶體使用率: ${MEMORY_USAGE}%"
if [ $MEMORY_USAGE -gt 80 ]; then
    print_warning "記憶體使用率過高！"
fi
echo ""

echo "磁碟空間:"
df -h
echo ""
DISK_USAGE=$(df -h $PROJECT_DIR | awk 'NR==2 {print $5}' | sed 's/%//')
echo "專案目錄磁碟使用率: ${DISK_USAGE}%"
if [ $DISK_USAGE -gt 80 ]; then
    print_warning "磁碟空間不足！"
fi
echo ""

# 3. 網路資訊
print_section "3. 網路資訊"
echo "IP 位址:"
hostname -I
echo ""
echo "網路介面:"
ip -brief addr
echo ""

# 4. 串口設備
print_section "4. 串口設備"
echo "USB 設備:"
lsusb
echo ""

echo "串口設備:"
if ls /dev/ttyUSB* 1> /dev/null 2>&1; then
    ls -l /dev/ttyUSB*
elif ls /dev/ttyACM* 1> /dev/null 2>&1; then
    ls -l /dev/ttyACM*
else
    print_error "未找到串口設備 (ttyUSB* 或 ttyACM*)"
    echo "請檢查 USB to RS-485 轉換器是否已連接"
fi
echo ""

echo "用戶群組 (檢查 dialout):"
groups
if groups | grep -q dialout; then
    echo "✓ 用戶在 dialout 群組中"
else
    print_error "用戶不在 dialout 群組中！需要執行: sudo usermod -a -G dialout \$USER"
fi
echo ""

# 5. Python 環境
print_section "5. Python 環境"
echo "Python 版本:"
python3 --version
echo ""

echo "虛擬環境:"
if [ -d "$PROJECT_DIR/venv" ]; then
    echo "✓ 虛擬環境存在"
    
    # 啟動虛擬環境並檢查套件
    source "$PROJECT_DIR/venv/bin/activate"
    echo ""
    echo "已安裝的套件:"
    pip list | grep -E "pymodbus|pyserial"
    deactivate
else
    print_error "虛擬環境不存在！需要執行: python3 -m venv venv"
fi
echo ""

# 6. 專案配置
print_section "6. 專案配置"
CONFIG_FILE="$PROJECT_DIR/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "✓ 配置檔案存在"
    echo ""
    echo "配置內容:"
    cat "$CONFIG_FILE"
    echo ""
    
    # 檢查配置是否有效
    if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "✓ 配置檔案格式正確"
    else
        print_error "配置檔案格式錯誤！"
    fi
else
    print_error "配置檔案不存在: $CONFIG_FILE"
fi
echo ""

# 7. 數據目錄
print_section "7. 數據目錄"
DATA_DIR="$PROJECT_DIR/data"
if [ -d "$DATA_DIR" ]; then
    echo "✓ 數據目錄存在"
    echo ""
    echo "目錄內容:"
    ls -lh "$DATA_DIR"
    echo ""
    
    if [ -d "$DATA_DIR/csv" ]; then
        CSV_COUNT=$(find "$DATA_DIR/csv" -name "*.csv" 2>/dev/null | wc -l)
        echo "CSV 檔案數量: $CSV_COUNT"
        if [ $CSV_COUNT -gt 0 ]; then
            echo "最新的 CSV 檔案:"
            ls -lt "$DATA_DIR/csv"/*.csv 2>/dev/null | head -3
        fi
    fi
    echo ""
else
    print_error "數據目錄不存在: $DATA_DIR"
fi
echo ""

# 8. 服務狀態
print_section "8. systemd 服務狀態"
SERVICE_NAME="modbus-reader.service"
if systemctl list-unit-files | grep -q $SERVICE_NAME; then
    echo "✓ 服務已安裝"
    echo ""
    
    echo "服務狀態:"
    sudo systemctl status $SERVICE_NAME --no-pager -l
    echo ""
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo "✓ 服務正在運行"
    else
        print_error "服務未運行！"
    fi
    
    if systemctl is-enabled --quiet $SERVICE_NAME; then
        echo "✓ 服務已啟用開機自動啟動"
    else
        print_warning "服務未啟用開機自動啟動"
    fi
else
    print_warning "服務未安裝"
    echo "需要執行: ./scripts/install_service.sh"
fi
echo ""

# 9. 最近的日誌
print_section "9. 最近的服務日誌"
if systemctl list-unit-files | grep -q $SERVICE_NAME; then
    echo "最近 20 行日誌:"
    sudo journalctl -u $SERVICE_NAME -n 20 --no-pager
    echo ""
    
    echo "錯誤日誌:"
    ERROR_COUNT=$(sudo journalctl -u $SERVICE_NAME --no-pager | grep -i error | wc -l)
    echo "錯誤數量: $ERROR_COUNT"
    if [ $ERROR_COUNT -gt 0 ]; then
        echo "最近的錯誤:"
        sudo journalctl -u $SERVICE_NAME --no-pager | grep -i error | tail -5
    fi
else
    echo "服務未安裝，無法查看日誌"
fi
echo ""

# 10. cron 任務
print_section "10. cron 任務"
echo "當前用戶的 cron 任務:"
crontab -l 2>/dev/null || echo "無 cron 任務"
echo ""

# 11. 備份狀態
print_section "11. 備份狀態"
BACKUP_DIR="$HOME/backups/modbus_data"
if [ -d "$BACKUP_DIR" ]; then
    echo "✓ 備份目錄存在"
    echo ""
    BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
    echo "備份數量: $BACKUP_COUNT"
    if [ $BACKUP_COUNT -gt 0 ]; then
        echo ""
        echo "最近的備份:"
        ls -lht "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -5
    fi
else
    print_warning "備份目錄不存在: $BACKUP_DIR"
fi
echo ""

# 12. 總結
print_header "診斷總結"

echo "檢查項目:"
echo ""

# 串口設備
if ls /dev/ttyUSB* 1> /dev/null 2>&1 || ls /dev/ttyACM* 1> /dev/null 2>&1; then
    echo "✓ 串口設備: 正常"
else
    echo "✗ 串口設備: 未找到"
fi

# 串口權限
if groups | grep -q dialout; then
    echo "✓ 串口權限: 正常"
else
    echo "✗ 串口權限: 需要添加到 dialout 群組"
fi

# 虛擬環境
if [ -d "$PROJECT_DIR/venv" ]; then
    echo "✓ Python 虛擬環境: 存在"
else
    echo "✗ Python 虛擬環境: 不存在"
fi

# 配置檔案
if [ -f "$CONFIG_FILE" ]; then
    echo "✓ 配置檔案: 存在"
else
    echo "✗ 配置檔案: 不存在"
fi

# 服務狀態
if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
    echo "✓ 服務狀態: 運行中"
elif systemctl list-unit-files | grep -q $SERVICE_NAME; then
    echo "⚠ 服務狀態: 已安裝但未運行"
else
    echo "✗ 服務狀態: 未安裝"
fi

# 磁碟空間
if [ $DISK_USAGE -lt 80 ]; then
    echo "✓ 磁碟空間: 充足 (${DISK_USAGE}%)"
else
    echo "⚠ 磁碟空間: 不足 (${DISK_USAGE}%)"
fi

# CPU 溫度
if [ ! -z "$TEMP_VALUE" ]; then
    if [ $TEMP_VALUE -lt 70 ]; then
        echo "✓ CPU 溫度: 正常 (${TEMP_VALUE}°C)"
    else
        echo "⚠ CPU 溫度: 過高 (${TEMP_VALUE}°C)"
    fi
fi

echo ""
print_header "診斷完成"
echo "如需技術支援，請將此報告儲存並提供:"
echo "  ./scripts/diagnose.sh > diagnostic_report_\$(date +%Y%m%d_%H%M%S).txt"
echo ""
