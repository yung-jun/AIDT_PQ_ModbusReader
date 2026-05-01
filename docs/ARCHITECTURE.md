# 專案架構總覽

## 系統架構

```
AIDT_PQ_ModbusReader/
├── src/                      # 核心源代碼
│   ├── __init__.py
│   ├── main.py              # 主程式邏輯
│   ├── reader/              # Modbus 讀取器模組
│   │   ├── __init__.py
│   │   ├── modbus_reader.py    # 基類
│   │   └── cpm10b_reader.py    # CPM-10B 專用讀取器
│   ├── storage/             # 數據存儲模組
│   │   ├── __init__.py
│   │   ├── base.py             # 存儲基類
│   │   ├── csv_storage.py      # CSV 存儲（唯一啟用的後端）
│   │   └── manager.py          # 存儲管理器
│   └── utils/               # 工具模組
│       ├── __init__.py
│       └── config.py           # 配置管理
├── scripts/                 # 自動化腳本
│   ├── setup_raspberry_pi.sh   # 初始化腳本
│   ├── install_service.sh      # 服務安裝腳本
│   ├── monitor_system.sh       # 系統監控腳本
│   ├── sync_to_gdrive.sh       # Google Drive 同步
│   ├── diagnose.sh             # 診斷腳本
│   └── modbus-reader.service   # systemd 服務檔案
├── docs/                    # 文件
│   ├── POLLING_MECHANISM.md         # 輪詢原理與時序
│   ├── SAMPLING_OPTIMIZATION.md     # 取樣速度最佳化說明
│   ├── SAMPLING_LIMIT_REPORT.md     # 取樣極限研究報告（實測數據）
│   ├── CSV_FORMAT.md                # CSV 欄位定義（使用者手冊）
│   ├── INCIDENT_20260501_SSH_UNREACHABLE.md  # 事故報告
│   ├── SCRIPTS_MECHANISM.md         # 自動化腳本說明
│   ├── GDRIVE_SYNC_QUICK_GUIDE.md   # Google Drive 設定
│   └── cpm_10b_spec.md              # CPM-10B 暫存器規格
├── data/                    # 數據目錄
│   └── csv/                    # CSV 檔案
├── logger/                  # 日誌目錄
├── config.json              # 配置檔案
├── run.py                   # 程式入口
├── requirements.txt         # Python 依賴
└── README.md                # 專案說明
```

---

## 核心流程

```
開機
  │
  ▼
systemd 啟動 modbus-reader.service
  │
  ▼
run.py → src/main.py
  │
  ▼
┌─────────────────────────────────────────┐
│              主迴圈                      │
│  ┌────────────────────────────────────┐ │
│  │ 1. 產生時間戳記                     │ │
│  │ 2. 依序讀取 Meter_1, 2, 3          │ │
│  │ 3. 合併存儲到 CSV                   │ │
│  │ 4. 等待至下個週期 (200ms, 5 Hz)      │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
  │
  ▼
每天 03:00 → sync_to_gdrive.sh → Google Drive
```

---

## 自動化任務

| 任務 | 頻率 | 執行方式 |
|------|------|---------|
| Modbus Reader | 開機啟動 | systemd 服務 |
| 系統監控 | 每 5 分鐘 | cron |
| Google Drive 同步 | 每天 03:00 | cron |

---

## 數據流

```
CPM-10B 電表
    │ RS-485
    ▼
USB to RS-485 轉換器
    │ /dev/ttyUSB0
    ▼
CPM10BReader (Modbus RTU)
    │
    ▼
CSVStorage
    │
    ▼
data/csv/modbus_data_YYYYMMDD.csv
    │ 每天 03:00
    ▼
Google Drive (rclone sync)
```

---

## 配置檔案 (config.json)

```json
{
    "serial_port": "/dev/ttyUSB0",
    "baudrate": 115200,
    "timeout_sec": 0.15,
    "poll_interval_sec": 0.2,
    "devices": [
        {"name": "Meter_1", "slave_id": 1},
        {"name": "Meter_2", "slave_id": 2},
        {"name": "Meter_3", "slave_id": 3}
    ],
    "storage": {
        "enabled": true,
        "types": ["csv"],
        "csv_directory": "data/csv"
    }
}
```

> `baudrate: 115200` 需先將每台 CPM-10B 前面板通訊速率改為 115200（新版韌體），詳見 [SAMPLING_OPTIMIZATION.md](SAMPLING_OPTIMIZATION.md)。

---

## 文件說明

| 文件 | 說明 |
|------|------|
| [POLLING_MECHANISM.md](POLLING_MECHANISM.md) | Modbus RTU 通訊原理與輪詢時序 |
| [SAMPLING_OPTIMIZATION.md](SAMPLING_OPTIMIZATION.md) | 取樣速度最佳化說明 |
| [SAMPLING_LIMIT_REPORT.md](SAMPLING_LIMIT_REPORT.md) | 取樣極限實測報告（含單台瓶頸分析） |
| [CSV_FORMAT.md](CSV_FORMAT.md) | CSV 欄位定義與使用說明 |
| [INCIDENT_20260501_SSH_UNREACHABLE.md](INCIDENT_20260501_SSH_UNREACHABLE.md) | 事故報告：SSH 無法連線（2026-05-01） |
| [SCRIPTS_MECHANISM.md](SCRIPTS_MECHANISM.md) | 自動化腳本說明 |
| [GDRIVE_SYNC_QUICK_GUIDE.md](GDRIVE_SYNC_QUICK_GUIDE.md) | Google Drive 設定 |
| [cpm_10b_spec.md](cpm_10b_spec.md) | CPM-10B 暫存器規格 |
