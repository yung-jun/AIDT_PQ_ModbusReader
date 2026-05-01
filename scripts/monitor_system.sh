#!/bin/bash

###############################################################################
# AIDT PQ Modbus Reader - 系統監控腳本
# 
# 此腳本會:
# 1. 檢查服務運行狀態
# 2. 檢查磁碟空間
# 3. 檢查 CPU 溫度
# 4. 檢查記憶體使用
# 5. 服務異常時自動重啟
#
# 使用方法:
#   chmod +x monitor_system.sh
#   ./monitor_system.sh
#
# 設定 cron 自動執行:
#   crontab -e
#   */5 * * * * /home/rennpi/AIDT_PQ_ModbusReader/scripts/monitor_system.sh
###############################################################################

# 配置
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE_NAME="modbus-reader.service"
LOG_FILE="$PROJECT_DIR/logger/monitor.log"
DATA_DIR="$PROJECT_DIR/data"

# 警告閾值
DISK_WARN_THRESHOLD=80      # 磁碟使用率警告閾值 (%)
TEMP_WARN_THRESHOLD=70      # CPU 溫度警告閾值 (°C)
MEMORY_WARN_THRESHOLD=80    # 記憶體使用率警告閾值 (%)

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

# 1. 檢查服務狀態
check_service() {
    log_info "檢查服務狀態..."
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "服務運行正常: $SERVICE_NAME"
        return 0
    else
        log_error "服務未運行: $SERVICE_NAME"
        log_info "嘗試重啟服務..."
        
        if sudo systemctl restart $SERVICE_NAME; then
            log_info "服務重啟成功"
            return 0
        else
            log_error "服務重啟失敗"
            return 1
        fi
    fi
}

# 2. 檢查磁碟空間
check_disk_space() {
    log_info "檢查磁碟空間..."
    
    # 檢查數據目錄所在的磁碟
    DISK_USAGE=$(df -h "$DATA_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    DISK_MOUNT=$(df -h "$DATA_DIR" | awk 'NR==2 {print $6}')
    
    log_info "磁碟使用率: ${DISK_USAGE}% (掛載點: $DISK_MOUNT)"
    
    if [ $DISK_USAGE -gt $DISK_WARN_THRESHOLD ]; then
        log_warn "磁碟使用率過高: ${DISK_USAGE}% (閾值: ${DISK_WARN_THRESHOLD}%)"
        
        # 顯示數據目錄大小
        DATA_SIZE=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
        log_info "數據目錄大小: $DATA_SIZE"
        
        return 1
    fi
    
    return 0
}

# 3. 檢查 CPU 溫度
check_temperature() {
    log_info "檢查 CPU 溫度..."
    
    if command -v vcgencmd &> /dev/null; then
        TEMP=$(vcgencmd measure_temp | sed 's/temp=//' | sed "s/'C//")
        TEMP_INT=${TEMP%.*}
        
        log_info "CPU 溫度: ${TEMP}°C"
        
        if [ $TEMP_INT -gt $TEMP_WARN_THRESHOLD ]; then
            log_warn "CPU 溫度過高: ${TEMP}°C (閾值: ${TEMP_WARN_THRESHOLD}°C)"
            return 1
        fi
    else
        log_warn "無法獲取 CPU 溫度 (vcgencmd 不可用)"
    fi
    
    return 0
}

# 4. 檢查記憶體使用
check_memory() {
    log_info "檢查記憶體使用..."
    
    MEMORY_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    MEMORY_USED=$(free -h | awk 'NR==2 {print $3}')
    MEMORY_TOTAL=$(free -h | awk 'NR==2 {print $2}')
    
    log_info "記憶體使用: ${MEMORY_USED}/${MEMORY_TOTAL} (${MEMORY_USAGE}%)"
    
    if [ $MEMORY_USAGE -gt $MEMORY_WARN_THRESHOLD ]; then
        log_warn "記憶體使用率過高: ${MEMORY_USAGE}% (閾值: ${MEMORY_WARN_THRESHOLD}%)"
        return 1
    fi
    
    return 0
}

# 主程式
main() {
    log_info "========== 開始系統監控 =========="
    
    # 執行所有檢查
    check_service
    SERVICE_STATUS=$?
    
    check_disk_space
    DISK_STATUS=$?
    
    check_temperature
    TEMP_STATUS=$?
    
    check_memory
    MEMORY_STATUS=$?
    
    # 總結
    if [ $SERVICE_STATUS -eq 0 ] && [ $DISK_STATUS -eq 0 ] && [ $TEMP_STATUS -eq 0 ] && [ $MEMORY_STATUS -eq 0 ]; then
        log_info "所有檢查通過，系統運行正常"
    else
        log_warn "部分檢查未通過，請注意"
    fi
    
    log_info "========== 監控完成 =========="
    echo "" >> "$LOG_FILE"
}

# 執行主程式
main
