#!/bin/bash

###############################################################################
# AIDT PQ Modbus Reader - 服務安裝腳本
# 
# 此腳本會:
# 1. 複製 systemd 服務檔案
# 2. 啟用開機自動啟動
# 3. 啟動服務
# 4. 設定日誌輪轉
# 5. 設定 cron 任務
#
# 使用方法:
#   chmod +x install_service.sh
#   ./install_service.sh
###############################################################################

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# 獲取專案路徑
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE_FILE="$SCRIPT_DIR/modbus-reader.service"
SERVICE_NAME="modbus-reader.service"

log_info "專案目錄: $PROJECT_DIR"

# 1. 檢查服務檔案是否存在
if [ ! -f "$SERVICE_FILE" ]; then
    log_error "服務檔案不存在: $SERVICE_FILE"
    exit 1
fi

# 2. 更新服務檔案中的路徑和使用者
log_info "更新服務檔案路徑..."
TEMP_SERVICE="/tmp/modbus-reader.service"
CURRENT_USER=$(whoami)
log_info "使用者: $CURRENT_USER"

# 替換 __USER__ 和 __PROJECT_DIR__ 佔位符
sed -e "s|__USER__|$CURRENT_USER|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    "$SERVICE_FILE" > "$TEMP_SERVICE"

# 3. 複製服務檔案到 systemd 目錄
log_info "安裝 systemd 服務..."
sudo cp "$TEMP_SERVICE" /etc/systemd/system/$SERVICE_NAME
sudo chmod 644 /etc/systemd/system/$SERVICE_NAME

# 4. 重新載入 systemd
log_info "重新載入 systemd..."
sudo systemctl daemon-reload

# 5. 啟用開機自動啟動
log_info "啟用開機自動啟動..."
sudo systemctl enable $SERVICE_NAME

# 6. 啟動服務
log_info "啟動服務..."
sudo systemctl start $SERVICE_NAME

# 7. 檢查服務狀態
sleep 2
if sudo systemctl is-active --quiet $SERVICE_NAME; then
    log_info "服務啟動成功"
else
    log_error "服務啟動失敗"
    sudo systemctl status $SERVICE_NAME
    exit 1
fi

# 8. 設定日誌輪轉
log_info "設定日誌輪轉..."
LOGROTATE_CONF="/etc/logrotate.d/modbus-reader"
sudo tee $LOGROTATE_CONF > /dev/null <<EOF
$PROJECT_DIR/logger/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $USER $USER
}
EOF

log_info "日誌輪轉設定完成"

# 9. 設定 cron 任務
log_info "設定 cron 任務..."

# 設定監控腳本
CRON_MONITOR="$SCRIPT_DIR/monitor_system.sh"

# 給予執行權限
chmod +x "$CRON_MONITOR"

# 添加 cron 任務（只保留監控）
(crontab -l 2>/dev/null | grep -v "$CRON_MONITOR"; echo "# AIDT PQ Modbus Reader - 系統監控 (每 5 分鐘)"; echo "*/5 * * * * $CRON_MONITOR") | crontab -

log_info "cron 任務設定完成"

# 10. 設定 Google Drive 同步（可選）
echo ""
log_info "========== Google Drive 雲端備份設定 =========="
echo ""
log_warn "是否要設定 Google Drive 自動同步? (y/N)"
read -p "選擇: " SETUP_GDRIVE

if [[ "$SETUP_GDRIVE" =~ ^[Yy]$ ]]; then
    log_info "開始設定 Google Drive 同步..."
    
    # 檢查 rclone 是否安裝
    if ! command -v rclone &> /dev/null; then
        log_info "安裝 rclone..."
        sudo apt update
        sudo apt install -y rclone
    else
        log_info "rclone 已安裝"
    fi
    
    # 檢查是否已配置且可連接
    GDRIVE_CONFIGURED=false
    GDRIVE_CONNECTED=false
    
    if rclone listremotes | grep -q "gdrive:"; then
        log_info "Google Drive 已配置，測試連接..."
        if rclone lsd gdrive: &> /dev/null; then
            log_info "Google Drive 連接成功"
            GDRIVE_CONFIGURED=true
            GDRIVE_CONNECTED=true
        else
            log_warn "Google Drive 配置存在但連接失敗"
            echo ""
            read -p "是否要重新配置 Google Drive? (y/N): " RECONFIG
            if [[ "$RECONFIG" =~ ^[Yy]$ ]]; then
                log_info "刪除舊配置..."
                rclone config delete gdrive
                GDRIVE_CONFIGURED=false
            else
                log_info "保留現有配置，稍後手動修復"
                GDRIVE_CONFIGURED=true
            fi
        fi
    fi
    
    # 如果未配置，開始配置流程
    if [ "$GDRIVE_CONFIGURED" = false ]; then
        log_warn "需要配置 Google Drive（Headless 模式）"
        echo ""
        echo "=========================================="
        echo "  由於 Pi 沒有瀏覽器，請使用以下步驟："
        echo "=========================================="
        echo ""
        echo "步驟 1: 在你的電腦上安裝 rclone"
        echo "        https://rclone.org/downloads/"
        echo ""
        echo "步驟 2: 在電腦上執行以下命令："
        echo "        rclone authorize \"drive\""
        echo ""
        echo "步驟 3: 瀏覽器授權後，複製顯示的 token JSON"
        echo ""
        echo "步驟 4: 在接下來的 rclone 配置中："
        echo "        - 選擇 'n' (New remote)"
        echo "        - 輸入名稱: gdrive"
        echo "        - 選擇 'drive' (Google Drive)"
        echo "        - scope 選擇 '1' (Full access)"
        echo "        - Use auto config? 選擇 'n' (關鍵！)"
        echo "        - 貼上你在電腦上獲得的 token"
        echo "        - 選擇 'y' (確認配置)"
        echo "        - 選擇 'q' (退出)"
        echo ""
        echo "=========================================="
        read -p "準備好 token 後按 Enter 開始配置..."
        
        rclone config
        
        # 配置後測試連接
        if rclone lsd gdrive: &> /dev/null; then
            GDRIVE_CONNECTED=true
        fi
    fi
    
    # 如果連接成功，設定 cron
    if [ "$GDRIVE_CONNECTED" = true ]; then
        log_info "Google Drive 連接成功"
        
        # 創建備份目錄
        rclone mkdir gdrive:AIDT_PQ_ModbusReader/csv 2>/dev/null
        
        # 設定 sync 腳本
        CRON_SYNC="$SCRIPT_DIR/sync_to_gdrive.sh"
        chmod +x "$CRON_SYNC"
        
        # 添加 cron 任務
        (crontab -l 2>/dev/null | grep -v "$CRON_SYNC"; echo "# AIDT PQ Modbus Reader - Google Drive 同步 (每天凌晨 3 點)"; echo "0 3 * * * $CRON_SYNC") | crontab -
        
        log_info "Google Drive 同步設定完成"
        log_info "每天凌晨 3 點自動同步 CSV 到 Google Drive"
    else
        log_error "Google Drive 連接失敗"
        echo ""
        echo "手動修復方法："
        echo "  1. 刪除舊配置: rclone config delete gdrive"
        echo "  2. 重新配置:   rclone config"
        echo "  3. 測試連接:   rclone lsd gdrive:"
    fi
else
    log_info "跳過 Google Drive 設定"
fi

# 11. 顯示服務狀態
echo ""
log_info "服務狀態:"
sudo systemctl status $SERVICE_NAME --no-pager

echo ""
log_info "========== 安裝完成 =========="
echo ""
log_info "常用命令:"
echo "  查看服務狀態: sudo systemctl status $SERVICE_NAME"
echo "  查看即時日誌: sudo journalctl -u $SERVICE_NAME -f"
echo "  停止服務:     sudo systemctl stop $SERVICE_NAME"
echo "  重啟服務:     sudo systemctl restart $SERVICE_NAME"
echo "  停用服務:     sudo systemctl disable $SERVICE_NAME"
echo ""
log_info "cron 任務:"
echo "  查看 cron 任務: crontab -l"
echo "  編輯 cron 任務: crontab -e"

if [[ "$SETUP_GDRIVE" =~ ^[Yy]$ ]]; then
    echo ""
    log_info "Google Drive 同步:"
    echo "  手動同步:      $SCRIPT_DIR/sync_to_gdrive.sh"
    echo "  查看同步日誌:  tail -f $PROJECT_DIR/logger/gdrive_sync.log"
    echo "  查看雲端檔案:  rclone ls gdrive:AIDT_PQ_ModbusReader/csv/"
fi

echo ""
