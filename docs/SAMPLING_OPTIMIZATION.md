# 取樣速度最佳化說明

本文件記錄 2026-05 對輪詢速度的系統性最佳化，包含動機、方法、效能數據與注意事項。

---

## 背景與動機

系統目標是對三台 CPM-10B/CPM-80 進行「準同步」取樣，用於故障診斷。

**CPM-10B/CPM-80 不支援硬體同步**，手冊中無以下功能：
- 外部同步觸發腳位 (External Sync Trigger)
- Master/Slave 同步模式
- SOE 時間戳記同步

因此只能透過軟體端縮短三台設備的輪詢時間差，以 `shared_timestamp` 標記為同一筆資料。

**最佳化前**（9600 baud）三台設備的最大時間差約 **580ms**，不適合故障診斷。

---

## 最佳化項目

### 1. Mega Block Read（最大貢獻）

CPM-10B 的電壓、電流、頻率暫存器位於連續的位址群（0x1000–0x101A），可在 **1 次 RTU 請求**內全部取回。

```
舊做法（9 次獨立請求）：
  read(0x1000) → Va
  read(0x1002) → Vb
  read(0x1004) → Vc
  read(0x1010) → Ia
  read(0x1012) → Ib
  read(0x1014) → Ic
  read(0x101A) → Frequency
  read(0x1032) → P_total
  read(0x1408) → Energy_Total

新做法（3 次請求）：
  block_read(0x1000, 14 floats) → Va[0] Vb[1] Vc[2] ... Ia[8] Ib[9] Ic[10] ... Freq[13]
  read(0x1032)                  → P_total
  read(0x1408)                  → Energy_Total
```

**Mega block 位址佈局（Float32，每個 2 個 word）：**

| Float Index | 位址 | 擷取欄位 |
|-------------|------|---------|
| 0 | 0x1000 | Va |
| 1 | 0x1002 | Vb |
| 2 | 0x1004 | Vc |
| 3–7 | 0x1006–0x100E | 跳過（Vab/Vbc/Vca 等線電壓） |
| 8 | 0x1010 | Ia |
| 9 | 0x1012 | Ib |
| 10 | 0x1014 | Ic |
| 11–12 | 0x1016–0x1018 | 跳過（In/Iavg 等） |
| 13 | 0x101A | Frequency |

> 中間位址（index 3–7、11–12）必須是儀表上有效的暫存器，否則 block read 會失敗。
> CPM-10B/CPM-80 為全功能電力分析儀，這些位址應對應線電壓與中性電流，應為有效。

### 2. Baudrate 9600 → 38400

RS-485 鏈路速率提升 4 倍，每次 RTU 訊框傳輸時間減少 75%。

> ⚠️ **此項需要對每台 CPM-10B 進行前面板操作**，詳見「硬體設定」章節。

### 3. 移除 `register_delay_ms`

原本每個暫存器讀取之間加入 10ms 延遲（共 90ms/台），實際上是不必要的。
pymodbus 已在協定層自動遵守 Modbus RTU 的 3.5-char 靜默間隔（38400 baud 時約 0.9ms）。

### 4. Timeout 0.3s → 0.05s

在 38400 baud 下，最長的回應（mega block，~65 bytes）約 18ms 即可完成，0.05s 仍有 2.7 倍餘裕。

### 5. Poll Interval 5s → 1s

實際輪詢時間遠低於 1s，可安全縮短輪詢週期。

---

## 效能數字

### RTU 訊框傳輸時間計算（38400 baud，10 bits/byte）

| 請求類型 | 請求 | 靜默 | 回應 | 合計 |
|---------|------|------|------|------|
| Mega block (28 regs) | 8 bytes ≈ 2.1ms | 0.9ms | ~65 bytes ≈ 17ms | **~20ms** |
| 單一 Float32 (2 regs) | 8 bytes ≈ 2.1ms | 0.9ms | ~10 bytes ≈ 2.6ms | **~6ms** |

### 每輪時間估算

| | 9600 baud（舊） | 38400 baud（新） |
|--|---------------|----------------|
| 請求次數/台 | 9 次 | 3 次 |
| 每台耗時 | ~22ms×9 + 10ms×9 = **288ms** | ~20ms + 6ms×2 = **~32ms** |
| 3 台合計 | **~864ms** | **~96ms** |
| 3 台最大時間差 | ~578ms | ~64ms |
| poll_interval_sec | 5s | 1s |

---

## 自動降回機制

若 mega block 讀取失敗（儀表拒絕中間位址），程式自動切換為 **分拆模式（5 次請求）**，不中斷資料收集。

```
log 訊息：Slave X: mega block failed, falling back to split reads
```

分拆模式下：
- 電壓 block：0x1000, 3 floats（Va/Vb/Vc）
- 電流 block：0x1010, 3 floats（Ia/Ib/Ic）
- Frequency：0x101A 單次
- P_total：0x1032 單次
- Energy_Total：0x1408 單次

降回後效能退回至 38400 baud × 5 次 ≈ **62ms/台，~186ms/輪**，仍比舊版 9600 baud 快約 4.6 倍。

---

## 硬體設定（必做）

**在啟動服務前，必須先把三台 CPM-10B 的通訊速率改為 38400 bps。**

若未先設定儀表就啟動服務，主站與從站波特率不符，將完全無法通訊，所有讀值為 None。

### 設定步驟（以 CPM-10B 前面板為例）

1. 進入 `COMM` 或 `Setup → Communication` 選單
2. 將 `Baud Rate` 設為 `38400`
3. 確認 `Parity: None`、`Stop Bits: 1`（與 config.json 一致）
4. 儲存設定，對三台重複相同操作

---

## config.json 對應設定

```json
{
    "baudrate": 38400,
    "timeout_sec": 0.05,
    "poll_interval_sec": 1
}
```

（`register_delay_ms` 已移除）

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| [src/reader/cpm10b_reader.py](../src/reader/cpm10b_reader.py) | `_poll_mega()` / `_poll_split()` / `poll_device()` |
| [src/reader/modbus_reader.py](../src/reader/modbus_reader.py) | `read_float_block()` 方法 |
| [config.json](../config.json) | baudrate / timeout_sec / poll_interval_sec |
