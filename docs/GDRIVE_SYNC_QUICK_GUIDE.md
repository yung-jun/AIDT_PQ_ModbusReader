# Google Drive CSV 自動同步 - 快速指南

## 功能說明

- ✅ 只同步 CSV 檔案（不含 SQLite）
- ✅ 每天凌晨 3 點自動同步
- ✅ 增量更新（只上傳變更的檔案）
- ✅ 每天約 4.3 MB，15GB 可存 9.5 年

---

## 安裝方式

### 執行 install_service.sh（推薦）

```bash
cd /home/rennpi/AIDT_PQ_ModbusReader
./scripts/install_service.sh
```

安裝過程中會詢問：
```
是否要設定 Google Drive 自動同步? (y/N)
選擇: y
```

然後按照提示完成 Google Drive 授權即可。

---

## Google Drive 目錄結構

```
Google Drive
└── AIDT_PQ_ModbusReader/
    └── csv/
        ├── modbus_data_20251201.csv (4.3 MB)
        ├── modbus_data_20251202.csv (4.3 MB)
        ├── modbus_data_20251203.csv (4.3 MB)
        └── ...
```

---

## 常用命令

```bash
# 手動同步
./scripts/sync_to_gdrive.sh

# 查看 Google Drive 檔案
rclone ls gdrive:AIDT_PQ_ModbusReader/csv/

# 下載特定日期的 CSV
rclone copy gdrive:AIDT_PQ_ModbusReader/csv/modbus_data_20251208.csv ./

# 查看同步日誌
tail -f logger/gdrive_sync.log

# 查看 cron 任務
crontab -l
```

---

## 空間估算

| 項目 | 數值 |
|------|------|
| 每日 CSV 大小 | ~4.3 MB |
| Google Drive 免費空間 | 15 GB |
| 可保存天數 | ~3,488 天 (約 9.5 年) |

---

## 在網頁查看數據

1. 開啟 [Google Drive](https://drive.google.com)
2. 進入 `AIDT_PQ_ModbusReader/csv/`
3. 點擊任何 CSV 檔案即可預覽數據

---

## 故障排除

### rclone 未安裝
```bash
sudo apt install -y rclone
```

### Google Drive 未配置
```bash
rclone config
```

### 授權過期
```bash
rclone config reconnect gdrive:
```

### 測試連接
```bash
rclone lsd gdrive:
```

---

## 相關檔案

- 同步腳本: `scripts/sync_to_gdrive.sh`
- 同步日誌: `logger/gdrive_sync.log`
- 詳細日誌: `logger/gdrive_sync.log.detailed`
