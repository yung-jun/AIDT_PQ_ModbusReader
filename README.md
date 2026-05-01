# AIDT PQ Modbus Reader

電力品質監測系統 - 用於讀取 CPM-10B 電力品質分析儀數據

## 專案結構

```
AIDT_PQ_ModbusReader/
├── src/                      # 核心源代碼
│   ├── reader/              # Modbus 讀取器模組
│   │   ├── modbus_reader.py    # Modbus 讀取器基類
│   │   └── cpm10b_reader.py    # CPM-10B 專用讀取器
│   ├── storage/             # 數據存儲模組
│   │   ├── base.py             # 存儲基類
│   │   ├── csv_storage.py      # CSV 存儲
│   │   └── manager.py          # 存儲管理器
│   └── utils/               # 工具模組
│       └── config.py           # 配置管理
├── config.json              # 配置文件
├── main.py                  # 主程式入口
├── requirements.txt         # Python 依賴
├── data/                    # 數據目錄
│   └── csv/                # CSV 數據文件
└── logger/                  # 日誌目錄
```

## 🚀 Raspberry Pi 部署

本專案支援在 Raspberry Pi 上長期運行,適合用於連續數據採集（一個月或更長時間）。

> 📖 **完整部署方案**: 請先閱讀 [Raspberry Pi 部署方案總結](RASPBERRY_PI_DEPLOYMENT_SUMMARY.md) 了解整體架構

### 快速部署 (30 分鐘)

```bash
# 1. 上傳專案到 Raspberry Pi
scp -r AIDT_PQ_ModbusReader pi@<raspberry-pi-ip>:~/

# 2. SSH 連接並執行自動安裝
ssh pi@<raspberry-pi-ip>
cd ~/AIDT_PQ_ModbusReader
chmod +x scripts/*.sh
./scripts/setup_raspberry_pi.sh

# 3. 編輯配置 (修改串口為 /dev/ttyUSB0)
nano config.json

# 4. 安裝為系統服務（會詢問是否設定 Google Drive）
./scripts/install_service.sh
```

[WARN] 下一步操作:
  1. 編輯 config.json，將 serial_port 改為 /dev/ttyUSB0
  2. 重新登入以使串口權限生效: logout 或 exit
  3. 測試運行: cd /home/rennpi/AIDT_PQ_ModbusReader && source venv/bin/activate && python run.py
  4. 設定自動啟動: sudo cp scripts/modbus-reader.service /etc/systemd/system/



### 部署後功能

✅ **自動啟動**: 開機自動啟動 Modbus Reader  
✅ **雲端備份**: 每天自動同步 CSV 到 Google Drive  
✅ **自動監控**: 每 5 分鐘檢查系統健康狀態  
✅ **自動重啟**: 服務異常時自動重啟  
✅ **日誌管理**: 自動輪轉日誌，避免磁碟空間不足  

### 相關文件

- 📖 [輪詢機制說明](docs/POLLING_MECHANISM.md) - Modbus RTU 通訊原理
- 📖 [腳本機制說明](docs/SCRIPTS_MECHANISM.md) - 自動化腳本說明
- 📖 [Google Drive 同步](docs/GDRIVE_SYNC_QUICK_GUIDE.md) - 雲端備份設定

---

## 快速開始 (Windows/開發環境)

### 1. 安裝依賴

```bash
pip install -r requirements.txt
```

### 2. 配置

編輯 `config.json`:

```json
{
    "serial_port": "COM7",
    "baudrate": 9600,
    "devices": [
        {"name": "Meter_1", "slave_id": 1}
    ],
    "storage": {
        "enabled": true,
        "types": ["csv"]
    }
}
```

### 3. 運行程式

```bash
python run.py
```

## 功能特性

### 數據讀取
- 支援 CPM-10B 電力品質分析儀
- 讀取電壓、電流、功率、頻率、電能等參數
- 可同時監測多個設備

### 數據存儲
- **CSV 格式**: 方便 Excel 分析和 Google Drive 同步
- 自動按日期分檔

### 模組化設計
- 基於抽象基類的可擴展架構
- 易於添加新的設備類型
- 易於添加新的存儲方式

## 使用示例

### 基本使用

```python
from src import CPM10BReader, StorageManager, load_config

# 載入配置
config = load_config("config.json")

# 創建讀取器
reader = CPM10BReader(config)

# 連接並讀取數據
if reader.connect():
    data = reader.poll_device({"name": "Meter_1", "slave_id": 1})
    print(data)
    reader.disconnect()
```

### 自定義存儲

```python
from src.storage import CSVStorage, SQLiteStorage

# 只使用 CSV 存儲
csv_storage = CSVStorage("custom/path")
csv_storage.save(data)
csv_storage.close()
```

## 配置說明

| 參數 | 說明 | 目前值 |
|------|------|--------|
| `serial_port` | 串口端口 | /dev/ttyUSB0 |
| `baudrate` | 波特率（需與儀表一致） | 38400 |
| `timeout_sec` | 通訊超時（秒） | 0.05 |
| `poll_interval_sec` | 輪詢間隔（秒） | 1 |
| `storage.enabled` | 啟用存儲 | true |
| `storage.types` | 存儲類型 | ["csv"] |

> 取樣速度最佳化說明請參閱 [docs/SAMPLING_OPTIMIZATION.md](docs/SAMPLING_OPTIMIZATION.md)。

## 擴展開發

### 添加新的設備類型

繼承 `ModbusReader` 基類:

```python
from src.reader import ModbusReader

class MyDeviceReader(ModbusReader):
    def get_register_map(self):
        return [
            {"name": "param1", "address": 0x1000, "unit": "V"}
        ]
    
    def poll_device(self, device):
        # 實現輪詢邏輯
        pass
```

### 添加新的存儲方式

繼承 `BaseStorage`:

```python
from src.storage import BaseStorage

class MyStorage(BaseStorage):
    def save(self, data):
        # 實現保存邏輯
        pass
    
    def close(self):
        # 實現清理邏輯
        pass
```

## 版本歷史

- **v2.1.0** - 取樣速度最佳化：mega block read、baudrate 38400、移除 register_delay
- **v2.0.0** - 模組化重構，物件導向設計
- **v1.0.0** - 初始版本

## 授權

AIDT © 2025
