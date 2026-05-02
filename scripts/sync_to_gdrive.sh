#!/bin/bash

###############################################################################
# AIDT PQ Modbus Reader - Google Drive 雲端備份腳本（CSV 同步版本）
# 
# 此腳本會:
# 1. 直接同步 CSV 目錄到 Google Drive（不壓縮）
# 2. 只上傳變更的檔案（增量同步）
# 3. 記錄備份日誌
#
# 使用方法:
#   chmod +x sync_to_gdrive.sh
#   ./sync_to_gdrive.sh
#
# 設定 cron 自動執行:
#   crontab -e
#   0 3 * * * /home/rennpi/AIDT_PQ_ModbusReader/scripts/sync_to_gdrive.sh
###############################################################################

# 配置
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$PROJECT_DIR/data/csv"  # 只同步 CSV 目錄
GDRIVE_REMOTE="gdrive:AIDT_PQ_ModbusReader/csv"  # Google Drive 路徑
LOG_FILE="$PROJECT_DIR/logger/gdrive_sync.log"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日誌函數
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "[INFO] $1"
}

log_warn() {
    log "[WARN] $1"
}

log_error() {
    log "[ERROR] $1"
}

# 創建日誌目錄
mkdir -p "$(dirname "$LOG_FILE")"

log_info "========== 開始 Google Drive 同步 =========="

# 1. 檢查 rclone 是否安裝
if ! command -v rclone &> /dev/null; then
    log_error "rclone 未安裝，請先執行安裝腳本"
    log_error "sudo apt install rclone"
    exit 1
fi

# 2. 檢查 rclone 配置
if ! rclone listremotes | grep -q "gdrive:"; then
    log_error "rclone 未配置 Google Drive"
    log_error "請執行: rclone config"
    exit 1
fi

# 3. 檢查來源目錄
if [ ! -d "$SOURCE_DIR" ]; then
    log_error "來源目錄不存在: $SOURCE_DIR"
    exit 1
fi

# 4. 顯示同步資訊
log_info "來源目錄: $SOURCE_DIR"
log_info "目標路徑: $GDRIVE_REMOTE"

# 計算來源目錄大小
SOURCE_SIZE=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1)
log_info "來源目錄大小: $SOURCE_SIZE"

# 5. 同步到 Google Drive
log_info "開始同步..."

# 使用 rclone sync 同步目錄
# --progress: 顯示進度
# --transfers 4: 同時上傳 4 個檔案
# --checkers 8: 同時檢查 8 個檔案
# --stats 1m: 每分鐘顯示統計
# --log-file: 詳細日誌

if rclone sync "$SOURCE_DIR" "$GDRIVE_REMOTE" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --stats 1m \
    --min-age 1h \
    --log-file "$LOG_FILE.detailed" \
    --log-level INFO; then
    log_info "同步成功"
else
    log_error "同步失敗"
    exit 1
fi

# 6. 驗證同步
log_info "驗證同步..."

# 檢查 Google Drive 目錄
if rclone lsd "$GDRIVE_REMOTE" &> /dev/null; then
    log_info "驗證成功: 目錄已存在於 Google Drive"
    
    # 顯示 Google Drive 目錄結構
    log_info "Google Drive 目錄結構:"
    rclone tree "$GDRIVE_REMOTE" --level 2 | tee -a "$LOG_FILE"
else
    log_error "驗證失敗: 目錄未找到於 Google Drive"
    exit 1
fi

# 7. 顯示同步統計
log_info "同步統計:"
rclone size "$GDRIVE_REMOTE" | tee -a "$LOG_FILE"

# 8. 顯示最近修改的檔案
log_info "最近同步的檔案 (前 10 個):"
rclone lsl "$GDRIVE_REMOTE" --max-depth 2 | sort -k 2 -r | head -n 10 | tee -a "$LOG_FILE"

# 9. 顯示本地磁碟使用情況
DISK_USAGE=$(df -h "$SOURCE_DIR" | awk 'NR==2 {print $5}')
log_info "本地磁碟使用率: $DISK_USAGE"

log_info "========== Google Drive 同步完成 =========="
echo ""
