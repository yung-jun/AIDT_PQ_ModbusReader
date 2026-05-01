# Scripts 維護機制說明

本文件說明 AIDT PQ Modbus Reader 系統的自動化維護腳本機制。

---

## 腳本總覽

| 腳本名稱 | 功能 | 執行方式 | 執行頻率 |
|---------|------|---------|---------|
| `setup_raspberry_pi.sh` | 初始化 Raspberry Pi 環境 | 手動執行 | 一次性 |
| `install_service.sh` | 安裝 systemd 服務 | 手動執行 | 一次性 |
| `monitor_system.sh` | 系統監控與自動修復 | cron 自動 | 每 5 分鐘 |
| `sync_to_gdrive.sh` | Google Drive 同步 | cron 自動 | 每天凌晨 3 點 |
| `diagnose.sh` | 系統診斷工具 | 手動執行 | 需要時 |

---

## 1. 初始化腳本 (setup_raspberry_pi.sh)

### 功能說明

首次部署時執行，自動完成 Raspberry Pi 環境設定。

### 執行步驟

```bash
chmod +x scripts/setup_raspberry_pi.sh
./scripts/setup_raspberry_pi.sh
```

### 自動化任務

1. 更新系統套件：`sudo apt update && sudo apt upgrade -y`
2. 安裝必要軟體：python3, python3-pip, python3-venv, git, htop
3. 設定串口權限：`sudo usermod -a -G dialout $USER`
4. 創建 Python 虛擬環境：`python3 -m venv venv`
5. 安裝 Python 依賴：`pip install -r requirements.txt`
6. 創建數據目錄：`mkdir -p data/csv logger`

### 完成後提示

```
下一步操作:
  1. 編輯 config.json，將 serial_port 改為 /dev/ttyUSB0
  2. 重新登入以使串口權限生效
  3. 測試運行: source venv/bin/activate && python run.py
  4. 設定自動啟動: ./scripts/install_service.sh
```

---

## 2. 服務安裝腳本 (install_service.sh)

### 功能說明

將 Modbus Reader 安裝為 systemd 服務，實現開機自動啟動。

### 執行步驟

```bash
chmod +x scripts/install_service.sh
./scripts/install_service.sh
```

### 安裝流程

1. 更新服務檔案（替換 `__USER__` 和 `__PROJECT_DIR__`）
2. 複製到 `/etc/systemd/system/`
3. 啟用開機自動啟動
4. 啟動服務
5. 設定日誌輪轉
6. 設定 cron 任務（監控）
7. **詢問是否設定 Google Drive 同步**

### systemd 服務檔案

```ini
[Unit]
Description=AIDT PQ Modbus Reader Service
After=network.target

[Service]
Type=simple
User=__USER__
WorkingDirectory=__PROJECT_DIR__
ExecStart=__PROJECT_DIR__/venv/bin/python run.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 常用命令

```bash
# 查看服務狀態
sudo systemctl status modbus-reader.service

# 查看即時日誌
sudo journalctl -u modbus-reader.service -f

# 重啟服務
sudo systemctl restart modbus-reader.service

# 停止服務
sudo systemctl stop modbus-reader.service
```

---

## 3. 系統監控腳本 (monitor_system.sh)

### 功能說明

定期檢查系統狀態，自動修復服務異常。

### Cron 排程

```bash
# 每 5 分鐘執行一次
*/5 * * * * /home/rennpi/AIDT_PQ_ModbusReader/scripts/monitor_system.sh
```

### 監控項目

| 檢查項目 | 警告閾值 | 失敗時動作 |
|---------|---------|-----------|
| 服務狀態 | - | 自動重啟服務 |
| 磁碟空間 | 80% | 記錄警告 |
| CPU 溫度 | 70°C | 記錄警告 |
| 記憶體使用 | 80% | 記錄警告 |

### 監控流程

```
每 5 分鐘執行
    │
    ├─► 檢查服務狀態
    │   ├─ 運行中 ✓
    │   └─ 停止 ✗ → 自動重啟
    │
    ├─► 檢查磁碟空間
    │   ├─ < 80% ✓
    │   └─ ≥ 80% ⚠ → 記錄警告
    │
    ├─► 檢查 CPU 溫度
    │   ├─ < 70°C ✓
    │   └─ ≥ 70°C ⚠ → 記錄警告
    │
    ├─► 檢查記憶體
    │   ├─ < 80% ✓
    │   └─ ≥ 80% ⚠ → 記錄警告
    │
    └─► 寫入日誌 → logger/monitor.log
```

---

## 4. Google Drive 同步腳本 (sync_to_gdrive.sh)

### 功能說明

每天自動將 CSV 數據同步到 Google Drive。

### Cron 排程

```bash
# 每天凌晨 3 點執行
0 3 * * * /home/rennpi/AIDT_PQ_ModbusReader/scripts/sync_to_gdrive.sh
```

### 同步策略

| 項目 | 設定 |
|------|------|
| **同步來源** | `data/csv/` |
| **同步目標** | `gdrive:AIDT_PQ_ModbusReader/csv/` |
| **同步方式** | 增量同步（只上傳變更的檔案） |
| **每日大小** | ~4.3 MB |

### 同步流程

```
每天 03:00 執行
    │
    ├─► 檢查 rclone 配置
    │
    ├─► 同步 CSV 到 Google Drive
    │   rclone sync data/csv/ gdrive:AIDT_PQ_ModbusReader/csv/
    │
    ├─► 驗證同步結果
    │
    └─► 寫入日誌 → logger/gdrive_sync.log
```

### 常用命令

```bash
# 手動同步
./scripts/sync_to_gdrive.sh

# 查看 Google Drive 檔案
rclone ls gdrive:AIDT_PQ_ModbusReader/csv/

# 下載備份
rclone copy gdrive:AIDT_PQ_ModbusReader/csv/modbus_data_20251208.csv ./
```

---

## 5. 診斷腳本 (diagnose.sh)

### 功能說明

系統診斷工具，用於排查問題。

### 執行步驟

```bash
./scripts/diagnose.sh
```

### 診斷項目

- 系統資訊（OS、Python 版本）
- 硬體資源（CPU 溫度、記憶體、磁碟）
- 串口設備（/dev/ttyUSB*）
- 服務狀態
- 配置檔案
- 數據目錄

---

## 6. Cron 任務總覽

### 查看 cron 任務

```bash
crontab -l
```

### 任務清單

```bash
# AIDT PQ Modbus Reader - 系統監控 (每 5 分鐘)
*/5 * * * * /home/rennpi/AIDT_PQ_ModbusReader/scripts/monitor_system.sh

# AIDT PQ Modbus Reader - Google Drive 同步 (每天凌晨 3 點)
0 3 * * * /home/rennpi/AIDT_PQ_ModbusReader/scripts/sync_to_gdrive.sh
```

---

## 7. 日誌檔案

| 日誌類型 | 路徑 | 內容 |
|---------|------|------|
| 監控日誌 | `logger/monitor.log` | 系統監控記錄 |
| 同步日誌 | `logger/gdrive_sync.log` | Google Drive 同步記錄 |
| 服務日誌 | `journalctl -u modbus-reader` | 服務運行日誌 |

### 查看日誌

```bash
# 監控日誌
tail -f logger/monitor.log

# 同步日誌
tail -f logger/gdrive_sync.log

# 服務日誌
sudo journalctl -u modbus-reader.service -f
```

---

## 8. 常見問題排查

### 服務無法啟動

```bash
sudo systemctl status modbus-reader.service
sudo journalctl -u modbus-reader.service -n 50
```

### 串口權限問題

```bash
ls -l /dev/ttyUSB0
groups  # 確認是否在 dialout 群組
```

### Google Drive 同步失敗

```bash
rclone lsd gdrive:  # 測試連接
rclone config reconnect gdrive:  # 重新授權
```

---

## 9. 手動執行指令

```bash
# 初始化環境
./scripts/setup_raspberry_pi.sh

# 安裝服務
./scripts/install_service.sh

# 手動監控
./scripts/monitor_system.sh

# 手動同步
./scripts/sync_to_gdrive.sh

# 系統診斷
./scripts/diagnose.sh
```

---

## 總結

✅ **自動監控**：每 5 分鐘檢查系統狀態  
✅ **自動修復**：服務異常時自動重啟  
✅ **雲端備份**：每天同步 CSV 到 Google Drive  
✅ **詳細日誌**：記錄所有操作和警告  

確保系統穩定運行，數據安全可靠！
