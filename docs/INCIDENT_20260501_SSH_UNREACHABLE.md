# 事故報告：SSH 無法連線（2026-05-01）

## 事故摘要

**發生時間**：2026-05-01 約 17:00 CST  
**影響範圍**：Raspberry Pi 遠端 SSH 完全無法連線  
**根本原因**：Modbus baud rate 不一致導致輪詢迴圈無限 timeout，CPU 滿載  
**恢復方式**：物理重開機，更新程式碼後重啟服務  

---

## 事故經過

### 1. 觸發操作

為提升取樣速度，將三台 CPM-10B 電表前面板的通訊速率由 **9600 baud** 改為 **38400 baud**。

此時 `modbus-reader.service` **仍在運行**，config.json 中的 baudrate 尚未更新，仍為 9600。

### 2. 失效機制

```
電表：38400 baud
Service（舊 config）：9600 baud
        ↓
所有 Modbus read 回傳亂碼或無回應 → timeout
        ↓
pymodbus 預設 retries=3：每次 read 嘗試 4 次
0.3s timeout × 4 retries × 9 reads × 3 台 = 32.4s/輪
        ↓
poll_interval=5s，sleep_time = max(0, 5 - 32.4) = 0
        ↓
主迴圈完全沒有 sleep → CPU 100% 滿載
        ↓
SSH 無法連線
```

### 3. 症狀

- 遠端 SSH 連線逾時，無法進入系統
- 需物理操作（斷電重開機）恢復

---

## 修復方案

### 修復一：`main.py` — 強制最小 sleep（防止 CPU 滿載）

**檔案**：[src/main.py](../src/main.py)

```python
# 改前
sleep_time = max(0, config['poll_interval_sec'] - elapsed)

# 改後
sleep_time = max(0.5, config['poll_interval_sec'] - elapsed)
```

無論通訊是否失敗，每輪輪詢至少休息 0.5 秒，確保 CPU 有喘息空間，SSH 不會被 starve。

---

### 修復二：`modbus_reader.py` — 限制 pymodbus 重試次數與重連退避

**檔案**：[src/reader/modbus_reader.py](../src/reader/modbus_reader.py)

```python
self.client = ModbusSerialClient(
    ...
    retries=1,              # 預設 3，改為 1（每次 read 最多嘗試 2 次）
    reconnect_delay=0.1,    # 重連起始間隔 0.1s
    reconnect_delay_max=1.0 # 預設 300s，限制為 1s，防止指數退避卡住
)
```

---

### 修復三：`config.json` — 同步更新 baudrate 與 timeout

**檔案**：[config.json](../config.json)

```json
{
    "baudrate": 38400,
    "timeout_sec": 0.15,
    "poll_interval_sec": 1
}
```

`timeout_sec` 從 0.3 調整為 0.15，在 38400 baud 下（最長回應 ~20ms）仍有 7.5 倍餘裕，同時縮短錯誤時的等待時間。

---

## 最壞情況驗算（修復後）

全部通訊失敗時的 CPU 佔用：

```
0.15s timeout × 2 次嘗試 × 5 reads × 3 台 = 4.5s/輪
sleep = max(0.5, 1 - 4.5) = 0.5s

每輪週期 = 5s，CPU 休息比例 ≈ 10%
→ SSH 可存活
```

---

## 預防措施

### 正確的 baudrate 變更 SOP

1. **先停止服務**，再動電表設定：
   ```bash
   sudo systemctl stop modbus-reader.service
   ```
2. 修改所有電表前面板 baudrate（確保三台一致）
3. 更新 `config.json` 中的 `baudrate`
4. 重新啟動服務並確認 log 正常：
   ```bash
   sudo systemctl start modbus-reader.service
   journalctl -u modbus-reader.service -f
   ```

### 判斷 SSH 掉線原因

| 現象 | 可能原因 | 診斷方法 |
|------|---------|---------|
| 改 baudrate 後立即掉線 | baud rate 不一致，CPU 滿載 | 物理重開機，停服務再改設定 |
| 接上電表硬體後掉線 | USB 供電不足 / RS-485 EMI | 停服務後再接硬體，若仍掉線為硬體問題 |
| 無明顯操作觸發 | 服務 bug 或其他程序 | `top` 查 CPU，`journalctl` 查 log |

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| [src/main.py](../src/main.py) | 最小 sleep 保護 |
| [src/reader/modbus_reader.py](../src/reader/modbus_reader.py) | retries / reconnect_delay_max |
| [config.json](../config.json) | baudrate / timeout_sec |
| [docs/SAMPLING_OPTIMIZATION.md](SAMPLING_OPTIMIZATION.md) | 取樣速度最佳化背景 |
