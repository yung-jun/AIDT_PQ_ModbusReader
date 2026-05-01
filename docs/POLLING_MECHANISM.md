# Modbus RTU 輪詢原理

本文件說明 AIDT PQ Modbus Reader 系統的資料擷取機制與 Modbus RTU 通訊原理。

---

## 系統架構

```
┌─────────────────────────────────────────────────────────────────┐
│                      Raspberry Pi                                │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────┐ │
│  │   main.py   │───▶│ CPM10BReader │───▶│ ModbusSerialClient  │ │
│  │  (主迴圈)    │    │  (讀取器)     │    │    (pymodbus)       │ │
│  └─────────────┘    └──────────────┘    └──────────┬──────────┘ │
│         │                                          │            │
│         ▼                                          │            │
│  ┌─────────────┐                                   │            │
│  │StorageManager│                                  │            │
│  │ (CSV only) │                                   │            │
│  └─────────────┘                                   │            │
└────────────────────────────────────────────────────┼────────────┘
                                                     │
                                          ┌──────────▼──────────┐
                                          │  USB to RS-485      │
                                          │    轉換器            │
                                          └──────────┬──────────┘
                                                     │ RS-485 總線
                    ┌────────────────────────────────┼────────────────────┐
                    │                                │                    │
              ┌─────▼─────┐                   ┌──────▼────┐        ┌──────▼────┐
              │  Meter_1  │                   │  Meter_2  │        │  Meter_3  │
              │ (Slave 1) │                   │ (Slave 2) │        │ (Slave 3) │
              └───────────┘                   └───────────┘        └───────────┘
```

---

## 輪詢流程

### 主程式邏輯 (main.py)

```python
while True:
    shared_timestamp = datetime.now()      # 1️⃣ 產生統一時間戳記
    
    all_devices_data = []
    
    for device in [Meter_1, Meter_2, Meter_3]:   # 2️⃣ 依序輪詢
        data = reader.poll_device(device)        # 3️⃣ 讀取設備
        data['timestamp'] = shared_timestamp
        all_devices_data.append(data)
    
    storage_manager.save_combined(all_devices_data)  # 4️⃣ 合併存儲
    
    sleep(poll_interval - elapsed)           # 5️⃣ 等待下次輪詢
```

### 流程說明

| 步驟 | 動作 | 說明 |
|------|------|------|
| 1️⃣ | 產生時間戳記 | 所有電表共用同一個時間戳記 |
| 2️⃣ | 依序輪詢 | 因 RS-485 半雙工限制，必須串行讀取 |
| 3️⃣ | 讀取設備 | 透過 Modbus RTU 協定讀取暫存器 |
| 4️⃣ | 合併存儲 | 3 個電表資料合併成 CSV 單行 |
| 5️⃣ | 等待 | 扣除已用時間，等待至下次輪詢週期 |

---

## Modbus RTU 通訊原理

### RS-485 總線特性

- **半雙工 (Half-Duplex)**：同一時間只能單向通訊
- **主從架構 (Master-Slave)**：主站發起請求，從站回應
- **差分訊號**：抗干擾能力強，傳輸距離可達 1200 公尺

### 通訊流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                    RS-485 總線 (半雙工)                              │
│                                                                     │
│  主站 (Pi)                                                從站 (電表)│
│  ┌────────┐     請求 (Request)      ┌────────┐                      │
│  │        │ ──────────────────────▶ │        │                      │
│  │ Master │                         │ Slave  │                      │
│  │        │ ◀────────────────────── │   1    │                      │
│  └────────┘     回應 (Response)     └────────┘                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Modbus RTU 訊框格式

**請求訊框 (Master → Slave)：**

```
┌──────────┬──────────┬─────────────┬───────────┬──────────┐
│ Slave ID │ Function │ Start Addr  │   Count   │   CRC    │
│  1 byte  │  1 byte  │   2 bytes   │  2 bytes  │  2 bytes │
└──────────┴──────────┴─────────────┴───────────┴──────────┘
     01        03        10 00          00 02       XX XX
   (Slave 1) (讀取)   (地址 0x1000)  (讀2個寄存器)
```

**回應訊框 (Slave → Master)：**

```
┌──────────┬──────────┬────────────┬─────────────────┬──────────┐
│ Slave ID │ Function │ Byte Count │      Data       │   CRC    │
│  1 byte  │  1 byte  │   1 byte   │    N bytes      │  2 bytes │
└──────────┴──────────┴────────────┴─────────────────┴──────────┘
     01        03          04        XX XX XX XX        XX XX
                       (4 bytes)   (Float32 數值)
```

### Function Code 說明

| 代碼 | 名稱 | 說明 |
|------|------|------|
| 0x03 | Read Holding Registers | 讀取保持暫存器 |
| 0x04 | Read Input Registers | 讀取輸入暫存器 |
| 0x06 | Write Single Register | 寫入單一暫存器 |
| 0x10 | Write Multiple Registers | 寫入多個暫存器 |

---

## CPM-10B 暫存器對照表

每個電表讀取以下 16 個參數（詳細規格見 [cpm_10b_spec.md](cpm_10b_spec.md)）：

| 參數名稱 | 暫存器地址 | 資料格式 | 單位 | 說明 |
|----------|------------|----------|------|------|
| Va | 0x1000 | Float32 | V | A 相電壓 |
| Vb | 0x1002 | Float32 | V | B 相電壓 |
| Vc | 0x1004 | Float32 | V | C 相電壓 |
| Vab | 0x1008 | Float32 | V | A-B 線電壓 |
| Vbc | 0x100A | Float32 | V | B-C 線電壓 |
| Vca | 0x100C | Float32 | V | C-A 線電壓 |
| Ia | 0x1010 | Float32 | A | A 相電流 |
| Ib | 0x1012 | Float32 | A | B 相電流 |
| Ic | 0x1014 | Float32 | A | C 相電流 |
| Frequency | 0x1018 | Float32 | Hz | 電源頻率 |
| PF_A | 0x101C | Float32 | — | A 相功率因數 |
| PF_B | 0x101E | Float32 | — | B 相功率因數 |
| PF_C | 0x1020 | Float32 | — | C 相功率因數 |
| PF_avg | 0x1022 | Float32 | — | 三相平均功率因數 |
| P_total | 0x1032 | Float32 | W | 三相總有功功率 |
| Q_total | 0x103A | Float32 | VAR | 三相總無功功率 |

### Float32 解碼

CPM-10B 使用 **Big-Endian (ABCD)** 格式儲存浮點數：

```python
def decode_float(registers):
    # registers[0] = 高位 word, registers[1] = 低位 word
    raw_bytes = struct.pack('>HH', registers[0], registers[1])
    return struct.unpack('>f', raw_bytes)[0]
```

---

## 時序分析

### 單次輪詢時序圖（115200 baud，最佳化後）

```
時間軸 ──────────────────────────────────────────────────────────────▶

     │◀── Meter_1 ──▶│◀── Meter_2 ──▶│◀── Meter_3 ──▶│存儲│◀──── 等待 ────▶│
     ├────────────────┼────────────────┼────────────────┼────┼──────────────┤
     0              ~31ms            ~62ms           ~93ms ~126ms         200ms
     │                                                                      │
     └────────────────── poll_interval_sec (200ms) ─────────────────────────┘

  3 台最大時間差 ≈ 62ms；平均 cycle ≈ 126ms（38400 baud 時：~146ms）
```

### 每個電表的讀取順序（最佳化後：2 次 RTU 請求）

```
poll_device(Meter_1):
    ├── read_float_block(0x1000, 18 floats)  → Va[0], Vb[1], Vc[2],
    │                                           Vab[4], Vbc[5], Vca[6],
    │                                           Ia[8], Ib[9], Ic[10],
    │                                           Frequency[12],
    │                                           PF_A[14], PF_B[15], PF_C[16], PF_avg[17]
    └── read_float_block(0x1032, 5 floats)   → P_total[0], Q_total[4]

(重複 Meter_2, Meter_3...)
```

中間跳過的 index（3=Vavg, 7=VLavg, 11=Iavg, 13=Reserved）仍在 block 內傳輸，但程式不提取。

若 mega block 被儀表拒絕，自動降回分拆模式（6 次請求）：

```
poll_device(Meter_1) [fallback]:
    ├── read_float_block(0x1000, 3) → Va, Vb, Vc
    ├── read_float_block(0x1008, 3) → Vab, Vbc, Vca
    ├── read_float_block(0x1010, 3) → Ia, Ib, Ic
    ├── read_float_register(0x1018) → Frequency
    ├── read_float_block(0x101C, 4) → PF_A, PF_B, PF_C, PF_avg
    └── read_float_block(0x1032, 5) → P_total[0], Q_total[4]
```

> 詳細最佳化原理請參閱 [SAMPLING_OPTIMIZATION.md](SAMPLING_OPTIMIZATION.md)。

---

## 配置參數

| 參數 | 目前值 | 說明 |
|------|--------|------|
| `serial_port` | /dev/ttyUSB0 | RS-485 轉換器裝置路徑 |
| `baudrate` | **115200** | 傳輸速率 (bps)，需同步設定儀表 |
| `timeout_sec` | **0.15** | 通訊超時時間 (秒) |
| `poll_interval_sec` | **0.2** | 輪詢週期 (秒)，對應 5 Hz 取樣率 |

（`register_delay_ms` 已於最佳化時移除，pymodbus 自動處理 RTU 靜默間隔）

---

## 為什麼是串行輪詢？

> **RS-485 是半雙工總線**，同一時間只能有一個設備在傳輸資料。因此主站必須依序詢問每個從站，等待回應後才能詢問下一個，無法同時並行讀取多個電表。

CPM-10B/CPM-80 亦不具備硬體同步功能（無外部觸發腳位、無 SOE 時間戳），因此以下策略為最優解：

1. **Block Read 合併請求**：同一設備的連續位址一次讀取（已實現）
2. **提高 Baudrate**：115200 bps（已實現，需儀表前面板設定）
3. **共用時間戳記 `shared_timestamp`**：三台資料標記同一筆時間（已實現）
4. **多個 RS-485 通道**：每台儀表獨立 USB-RS485（需額外硬體，可進一步消除時間差）
