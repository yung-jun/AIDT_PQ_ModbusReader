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

CPM-10B 的電壓、電流、頻率、功率因數暫存器位於連續的位址群（0x1000–0x1022），可在 **1 次 RTU 請求**（18 floats）內全部取回。

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
  （共 8 欄，未含線電壓、PF、Q_total）

新做法（2 次請求，16 欄）：
  block_read(0x1000, 18 floats) → Va[0] Vb[1] Vc[2] Vab[4] Vbc[5] Vca[6]
                                   Ia[8] Ib[9] Ic[10] Freq[12]
                                   PF_A[14] PF_B[15] PF_C[16] PF_avg[17]
  block_read(0x1032, 5 floats)  → P_total[0] Q_total[4]
```

**Mega block 位址佈局（0x1000 起，Float32，每個 2 個 word）：**

| Float Index | 位址 | 欄位 | 備註 |
|-------------|------|------|------|
| 0 | 0x1000 | **Va** | 擷取 |
| 1 | 0x1002 | **Vb** | 擷取 |
| 2 | 0x1004 | **Vc** | 擷取 |
| 3 | 0x1006 | Vavg | 跳過 |
| 4 | 0x1008 | **Vab** | 擷取 |
| 5 | 0x100A | **Vbc** | 擷取 |
| 6 | 0x100C | **Vca** | 擷取 |
| 7 | 0x100E | VLavg | 跳過 |
| 8 | 0x1010 | **Ia** | 擷取 |
| 9 | 0x1012 | **Ib** | 擷取 |
| 10 | 0x1014 | **Ic** | 擷取 |
| 11 | 0x1016 | Iavg | 跳過 |
| 12 | 0x1018 | Reserved | 跳過 |
| 13 | 0x101A | **Frequency** | 擷取 |
| 14 | 0x101C | **PF_A** | 擷取 |
| 15 | 0x101E | **PF_B** | 擷取 |
| 16 | 0x1020 | **PF_C** | 擷取 |
| 17 | 0x1022 | **PF_avg** | 擷取 |

**Power block 位址佈局（0x1032 起，5 floats）：**

| Float Index | 位址 | 欄位 | 備註 |
|-------------|------|------|------|
| 0 | 0x1032 | **P_total** | 擷取 |
| 1 | 0x1034 | Q_A | 跳過 |
| 2 | 0x1036 | Q_B | 跳過 |
| 3 | 0x1038 | Q_C | 跳過 |
| 4 | 0x103A | **Q_total** | 擷取 |

> 跳過的 index 仍在 RTU 訊框內傳輸，只是程式不提取其值。所有位址均為 CPM-10B 有效暫存器（來源：A21-02-CPM-10B-Manual-EN-V12-251113.pdf）。

### 2. Baudrate 9600 → 115200

RS-485 鏈路速率提升 12 倍（9600 → 38400 → 115200），每次 RTU 訊框傳輸時間大幅縮短。

> ⚠️ **此項需要對每台 CPM-10B 進行前面板操作**，詳見「硬體設定」章節。新版韌體支援 115200（register 0x0071 = 6）。

### 3. 移除 `register_delay_ms`

原本每個暫存器讀取之間加入 10ms 延遲（共 90ms/台），實際上是不必要的。
pymodbus 已在協定層自動遵守 Modbus RTU 的 3.5-char 靜默間隔（115200 baud 時約 0.3ms）。

### 4. Timeout 0.3s → 0.15s

在 115200 baud 下，mega block 回應（~77 bytes）約 6.7ms 傳輸完成，加上 CPM-10B 韌體延遲 ~10ms，0.15s 仍有充足餘裕，並可在通訊中斷時快速 fail-fast。

### 5. Poll Interval 5s → 0.2s（5 Hz）

實際輪詢時間約 146ms，0.2s 週期在扣除 read 耗時後仍有 ~54ms sleep，足以維持精確取樣率並確保 SSH 存活。

---

## 效能數字

### RTU 訊框傳輸時間計算（115200 baud，10 bits/byte）

| 請求類型 | 請求 | 靜默 | 回應 | 傳輸合計 | +韌體延遲 | 總計 |
|---------|------|------|------|---------|---------|------|
| Mega block（18 floats = 36 regs） | 8 bytes ≈ 0.7ms | 0.3ms | ~77 bytes ≈ 6.7ms | ~7.7ms | ~10ms | **~18ms** |
| Power block（5 floats = 10 regs） | 8 bytes ≈ 0.7ms | 0.3ms | ~25 bytes ≈ 2.2ms | ~3.2ms | ~10ms | **~13ms** |
| 每台小計（2 次請求） | — | — | — | — | — | **~31ms** |

### 每輪時間估算

| | 9600 baud（舊） | 38400 baud | 115200 baud（現行） |
|--|---------------|------------|-------------------|
| 請求次數/台 | 9 次 | 2 次 | **2 次** |
| 每台耗時（傳輸 + 韌體） | ~288ms | ~46ms | **~31ms** |
| 3 台合計（理論） | ~864ms | ~138ms | **~93ms** |
| 3 台合計（實測平均） | — | ~146ms | **~126ms** |
| 3 台最大時間差 | ~578ms | ~92ms | **~62ms** |
| poll_interval_sec | 5s | 0.2s | **0.2s（5 Hz）** |

---

## 自動降回機制

若 mega block 讀取失敗（儀表拒絕中間位址），程式自動切換為 **分拆模式（6 次請求）**，不中斷資料收集。

```
log 訊息：Slave X: mega block failed, falling back to split reads
```

分拆模式下：
- 相電壓 block：0x1000, 3 floats（Va/Vb/Vc）
- 線電壓 block：0x1008, 3 floats（Vab/Vbc/Vca）
- 電流 block：0x1010, 3 floats（Ia/Ib/Ic）
- Frequency：0x101A 單次
- PF block：0x101C, 4 floats（PF_A/PF_B/PF_C/PF_avg）
- Power block：0x1032, 5 floats（P_total[0] / Q_total[4]）

降回後效能退回至 115200 baud × 6 次 ≈ **48ms/台，~144ms/輪**，仍符合 5 Hz 取樣率。

---

## 硬體設定（必做）

**在啟動服務前，必須先把三台 CPM-10B 的通訊速率改為 115200 bps。**

若未先設定儀表就啟動服務，主站與從站波特率不符，將完全無法通訊，所有讀值為 None。

### 設定步驟（以 CPM-10B 前面板為例）

1. 進入 `COMM` 或 `Setup → Communication` 選單
2. 將 `Baud Rate` 設為 `115200`（新版韌體選項 6）
3. 確認 `Parity: None`、`Stop Bits: 1`（與 config.json 一致）
4. 儲存設定，對三台重複相同操作

---

## config.json 對應設定

```json
{
    "baudrate": 115200,
    "timeout_sec": 0.15,
    "poll_interval_sec": 0.2
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
