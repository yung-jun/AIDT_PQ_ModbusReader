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
│   │   ├── sqlite_storage.py   # SQLite 存儲
│   │   └── manager.py          # 存儲管理器
│   └── utils/               # 工具模組
│       └── config.py           # 配置管理
├── config.json              # 配置文件
├── main.py                  # 主程式入口
├── requirements.txt         # Python 依賴
├── data/                    # 數據目錄
│   ├── csv/                # CSV 數據文件
│   └── modbus_data.db      # SQLite 數據庫
└── logger/                  # 日誌目錄
```

## 快速開始

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
        "types": ["csv", "sqlite"]
    }
}
```

### 3. 運行程式

```bash
python main.py
```

## 功能特性

### 📊 數據讀取
- 支援 CPM-10B 電力品質分析儀
- 讀取電壓、電流、功率、頻率、電能等參數
- 可同時監測多個設備

### 💾 數據存儲
- **CSV 格式**: 方便 Excel 分析
- **SQLite 數據庫**: 支持複雜查詢
- 可選擇啟用一種或多種存儲方式

### 🔧 模組化設計
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

| 參數 | 說明 | 默認值 |
|------|------|--------|
| `serial_port` | 串口端口 | COM7 |
| `baudrate` | 波特率 | 9600 |
| `poll_interval_sec` | 輪詢間隔(秒) | 5 |
| `storage.enabled` | 啟用存儲 | true |
| `storage.types` | 存儲類型 | ["csv", "sqlite"] |

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

- **v2.0.0** - 模組化重構,物件導向設計
- **v1.0.0** - 初始版本

## 授權

AIDT © 2025
