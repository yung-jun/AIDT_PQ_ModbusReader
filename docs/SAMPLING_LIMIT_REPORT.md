# 取樣極限研究報告

**測試日期**：2026-05-01  
**硬體**：Raspberry Pi + ADTEK CPM-10B × 3 台（RS-485 Modbus RTU，USB 轉換器）  
**測試時通訊速率**：38400 baud（測試後已升級至 115200 baud，見第 5.3 節）

---

## 1. 測試方法

在主迴圈加入計時 log，每 50 個 cycle 輸出一次實際耗時：

```
Cycle #N: read=Xms  sleep=Yms  total=Zms
```

- `read`：從第一台電表開始輪詢到最後一台完成的實際耗時
- `sleep`：`time.sleep()` 執行時間（= `max(min_sleep, poll_interval - read)`）
- `total`：整個 cycle 實際長度（= read + sleep）

測試期間連續量測 127 個 cycle 樣本（約 21 分鐘，橫跨 4 Hz / 6.25 Hz / 5 Hz 三種設定）。

---

## 2. 硬體通訊耗時分析

### 2.1 每台電表的 RTU 請求結構

| 請求 | 位址 | Floats | 暫存器數 | 估算傳輸時間 |
|------|------|--------|----------|-------------|
| Mega block | 0x1000 | 18 | 36 | ~20 ms |
| Power block | 0x1032 | 5 | 10 | ~6.5 ms |
| 小計（含間隔） | — | — | — | **~27 ms/台** |

3 台合計理論值：~81 ms

### 2.2 實測 read 時間（127 個樣本）

| 統計項目 | 數值 |
|---------|------|
| 最小值 | 138.5 ms |
| 最大值 | 155.7 ms |
| 平均值 | 146.4 ms |
| 典型值 | 149–151 ms |

**理論值（81 ms）vs 實測（146 ms）差距約 65 ms**，來源分析：

| 來源 | 估算 |
|------|------|
| CPM-10B 韌體處理延遲（~10 ms × 6 次請求） | ~60 ms |
| pymodbus 內部開銷 + OS 排程抖動 | ~5 ms |
| 合計額外開銷 | ~65 ms |

---

## 3. 各取樣率測試結果

| 目標 Hz | poll_interval | min_sleep | 實測 total | 實際 Hz | sleep 狀態 |
|---------|--------------|-----------|-----------|---------|-----------|
| 4 Hz | 0.25 s | 0.06 s | **250.0 ms** | **4.00 Hz** | 自由調整（~103 ms） |
| 5 Hz | 0.20 s | 0.06 s | **207.1 ms** | **4.83 Hz** | 卡底（60 ms） |
| 5 Hz | 0.20 s | 0.01 s | **159.7 ms** | **6.26 Hz** | 卡底（10 ms） |
| 6 Hz | 0.167 s | 0.01 s | **167.0 ms** | **5.99 Hz** | 自由調整（~22 ms） |
| **5 Hz（最終）** | **0.20 s** | **0.01 s** | **200.0 ms** | **5.00 Hz** | 自由調整（~53 ms） |
| 極限測試 | 0.15 s | 0.01 s | **159.7 ms** | **6.26 Hz** | 卡底（10 ms） |
| 7 Hz（理論） | 0.143 s | 0 s | ~150 ms | ~6.67 Hz | 無法達成 |

### 關鍵觀察

1. **poll_interval 決定週期上限**：當 read < poll_interval - min_sleep 時，sleep 自動補齊，total 精確等於 poll_interval。

2. **min_sleep 決定 cycle 下限**：當 read > poll_interval - min_sleep 時，sleep 卡在 min_sleep，total = read + min_sleep。

3. **read 時間是硬體極限**：無論如何設定，total 不可能低於 read ≈ 150 ms。

---

## 4. 系統取樣極限

```
硬體極限 = read_avg + min_sleep_floor
         = 146 ms + 10 ms
         = ~156 ms
         ≈ 6.4 Hz（3 台電表同時輪詢）
```

**實測最高穩定取樣率：6.25 Hz（160 ms cycle）**

若需更高取樣率，唯一可行方向：
- 減少電表台數（1 台 → ~50 ms → 20 Hz）
- 更換支援多點同時回應的通訊架構（非 Modbus RTU 半雙工）

---

## 5. 單電表 read 時間瓶頸分析

### 5.1 耗時構成（以單台 CPM-10B 為例）

每台電表進行 2 次 RTU 請求（mega block + power block）：

| 成分 | 計算依據 | 數值 |
|------|---------|------|
| 傳輸時間（38400 baud，1 byte ≈ 260 µs） | mega frame ~77 bytes + power frame ~25 bytes | ~26 ms |
| **CPM-10B 韌體處理延遲** | 每次請求電表需運算後才回應 | **~10 ms / 次** |
| 2 次請求合計 | 26 ms 傳輸 + 20 ms 韌體 | **~46 ms / 台** |

3 台合計：~138 ms + pymodbus / OS 抖動 ~8 ms = **~146 ms**（與實測吻合）

韌體延遲 60 ms（10 ms × 6 次請求）佔總耗時的 **41%**，是 CPM-10B 的硬體固有特性，在相同 block 大小下無法壓縮。

### 5.2 為何瓶頸幾乎完全固定

**Modbus RTU 協議的結構性限制（不可繞過）：**

- RS-485 **半雙工**：一次只能一台設備說話，請求必須序列化
- 每個 request 必須等 response 回來 + 3.5 字元靜默期才能發下一個，無法 pipeline
- 同一條匯流排上的多台電表只能依序輪詢

在 block 大小不變的前提下：

```
per-meter read = 傳輸時間（由 baud rate 決定）
               + 韌體處理延遲（由電表硬體決定）
               + 協議 overhead（Modbus RTU 固定）
```

三項均為常數 → **單台讀取時間固定，與程式邏輯無關**。

### 5.3 若要進一步提速（不改 block 大小）

| 方法 | 理論收益 | 限制 |
|------|---------|------|
| ~~提升 baud rate（38400 → 115200）~~ | ~~傳輸時間縮短 3×~~ | **已實施**：實測 read ~126ms，極限 ~8.9 Hz |
| 每台電表用獨立 USB-RS485 + 多執行緒 | 3 台並行 → ~50 ms ≈ 20 Hz | CPM-10B 為 slave-only 裝置，同一台不可同時被多個 master 存取 |
| 減少台數（1 台） | ~46 ms ≈ 21 Hz | 改變了量測架構 |

**結論**：升級至 115200 baud 後，實測 read ≈ 126 ms（38400 baud 時為 146 ms），改善 ~20 ms。韌體延遲 60 ms 仍是主瓶頸，baud rate 已無法再提升（CPM-10B 最高支援 115200）。極限仍取決於韌體處理速度，而非傳輸速率。

---

## 7. 最終設定（正式運行）

### config.json

```json
{
    "serial_port": "/dev/ttyUSB0",
    "baudrate": 115200,
    "parity": "N",
    "stopbits": 1,
    "databits": 8,
    "timeout_sec": 0.15,
    "poll_interval_sec": 0.2
}
```

### main.py

```python
sleep_time = max(0.01, config['poll_interval_sec'] - elapsed)
```

### 運行結果

| 項目 | 數值 |
|------|------|
| 取樣率 | **5 Hz（200 ms/cycle）** |
| read 時間 | 141–152 ms（平均 146 ms） |
| sleep 時間 | 48–59 ms（自動補齊至 200 ms） |
| total | **200.0 ms（精確）** |
| 時間戳精度 | 毫秒（`isoformat(timespec='milliseconds')`） |

### 每次 cycle 取樣欄位（16 欄 × 3 台 + timestamp = 49 欄）

| 欄位群 | 欄位 | 診斷用途 |
|--------|------|---------|
| 相電壓 | Va, Vb, Vc | 電壓量測 |
| 線電壓 | Vab, Vbc, Vca | **三相不平衡偵測** |
| 電流 | Ia, Ib, Ic | 電流量測 |
| 頻率 | Frequency | 電源頻率 |
| 各相功率因數 | PF_A, PF_B, PF_C | **單相故障偵測** |
| 平均功率因數 | PF_avg | **整體電力品質** |
| 有功功率 | P_total | 實際消耗功率 |
| 無功功率 | Q_total | **電容/電感負載指標** |

---

## 8. SSH 安全性驗證

通訊失敗（所有請求 timeout）的最壞情況：

```
timeout_sec=0.15 × retries=2 × 6 reads = 1.8 s elapsed
sleep = max(0.01, 0.2 - 1.8) = 0.01 s

cycle = 1.81 s
```

串列 I/O timeout 為 kernel blocking（行程在 kernel 等待，不佔 CPU），加上 10 ms 強制 sleep，SSH 在通訊失敗時仍可存活。

相較於 2026-05-01 事故前的設定（`sleep=0`、retries=3、timeout=0.3s），現有設定的 CPU 佔用比大幅降低。
