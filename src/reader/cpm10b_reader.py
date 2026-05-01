"""
CPM-10B 電力品質分析儀讀取器
"""
import time
import logging
from typing import Dict, List, Any, Optional
from .modbus_reader import ModbusReader

logger = logging.getLogger(__name__)

# CPM-10B Float32 Register Map (FC03, 0x1000 range, read-only)
# Source: A21-02-CPM-10B-Manual-EN-V12-251113.pdf
#
# Mega block: 0x1000–0x1023 (18 floats, 1 RTU request)
#   index  0 = Va      (0x1000)  Phase-A Voltage (V)
#   index  1 = Vb      (0x1002)  Phase-B Voltage (V)
#   index  2 = Vc      (0x1004)  Phase-C Voltage (V)
#   index  3 = Vavg    (0x1006)  Average Phase Voltage (V)   [skipped]
#   index  4 = Vab     (0x1008)  Line Voltage AB (V)
#   index  5 = Vbc     (0x100A)  Line Voltage BC (V)
#   index  6 = Vca     (0x100C)  Line Voltage CA (V)
#   index  7 = VLavg   (0x100E)  Average Line Voltage (V)    [skipped]
#   index  8 = Ia      (0x1010)  Phase-A Current (A)
#   index  9 = Ib      (0x1012)  Phase-B Current (A)
#   index 10 = Ic      (0x1014)  Phase-C Current (A)
#   index 11 = Iavg    (0x1016)  Average Current (A)         [skipped]
#   index 12 = Freq    (0x1018)  Frequency (Hz)
#   index 13 = ---     (0x101A)  Reserved                    [skipped]
#   index 14 = PF_A    (0x101C)  Phase-A Power Factor
#   index 15 = PF_B    (0x101E)  Phase-B Power Factor
#   index 16 = PF_C    (0x1020)  Phase-C Power Factor
#   index 17 = PF_avg  (0x1022)  Average Power Factor
#
# Power block: 0x1032–0x103B (5 floats, 1 RTU request)
#   index  0 = P_total (0x1032)  Total Active Power (W)
#   index  1 = Q_A     (0x1034)  Phase-A Reactive Power (VAR) [skipped]
#   index  2 = Q_B     (0x1036)  Phase-B Reactive Power (VAR) [skipped]
#   index  3 = Q_C     (0x1038)  Phase-C Reactive Power (VAR) [skipped]
#   index  4 = Q_total (0x103A)  Total Reactive Power (VAR)
#
# 若 mega block 被固件拒絕，自動降回 _poll_split（多次請求）。
_MEGA_ADDR   = 0x1000
_MEGA_COUNT  = 18

_POWER_ADDR  = 0x1032
_POWER_COUNT = 5


class CPM10BReader(ModbusReader):
    """CPM-10B 專用讀取器"""

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self.register_map = self.get_register_map()
        self._use_mega_block = True  # 首次失敗後自動降回分拆模式

    def get_register_map(self) -> List[Dict[str, Any]]:
        """CPM-10B Float32 暫存器對照表"""
        return [
            {"name": "Va",        "address": 0x1000, "unit": "V"},
            {"name": "Vb",        "address": 0x1002, "unit": "V"},
            {"name": "Vc",        "address": 0x1004, "unit": "V"},
            {"name": "Vab",       "address": 0x1008, "unit": "V"},
            {"name": "Vbc",       "address": 0x100A, "unit": "V"},
            {"name": "Vca",       "address": 0x100C, "unit": "V"},
            {"name": "Ia",        "address": 0x1010, "unit": "A"},
            {"name": "Ib",        "address": 0x1012, "unit": "A"},
            {"name": "Ic",        "address": 0x1014, "unit": "A"},
            {"name": "Frequency", "address": 0x1018, "unit": "Hz"},
            {"name": "PF_A",      "address": 0x101C, "unit": ""},
            {"name": "PF_B",      "address": 0x101E, "unit": ""},
            {"name": "PF_C",      "address": 0x1020, "unit": ""},
            {"name": "PF_avg",    "address": 0x1022, "unit": ""},
            {"name": "P_total",   "address": 0x1032, "unit": "W"},
            {"name": "Q_total",   "address": 0x103A, "unit": "VAR"},
        ]

    @staticmethod
    def _r(val: Optional[float]) -> Optional[float]:
        return round(val, 3) if val is not None else None

    def _poll_mega(self, slave_id: int, m: Dict) -> bool:
        """1 次 RTU 請求取得 Va/Vb/Vc/Vab/Vbc/Vca/Ia/Ib/Ic/Freq/PF。失敗回傳 False。"""
        blk = self.read_float_block(slave_id, _MEGA_ADDR, _MEGA_COUNT)
        if blk[0] is None:
            return False
        m["Va"],    m["Vb"],    m["Vc"]    = self._r(blk[0]),  self._r(blk[1]),  self._r(blk[2])
        m["Vab"],   m["Vbc"],   m["Vca"]   = self._r(blk[4]),  self._r(blk[5]),  self._r(blk[6])
        m["Ia"],    m["Ib"],    m["Ic"]    = self._r(blk[8]),  self._r(blk[9]),  self._r(blk[10])
        m["Frequency"]                     = self._r(blk[12])
        m["PF_A"],  m["PF_B"],  m["PF_C"] = self._r(blk[14]), self._r(blk[15]), self._r(blk[16])
        m["PF_avg"]                        = self._r(blk[17])
        return True

    def _poll_split(self, slave_id: int, m: Dict):
        """降回模式：分次 RTU 請求讀取。"""
        va, vb, vc = self.read_float_block(slave_id, 0x1000, 3)
        m["Va"], m["Vb"], m["Vc"] = self._r(va), self._r(vb), self._r(vc)

        vab, vbc, vca = self.read_float_block(slave_id, 0x1008, 3)
        m["Vab"], m["Vbc"], m["Vca"] = self._r(vab), self._r(vbc), self._r(vca)

        ia, ib, ic = self.read_float_block(slave_id, 0x1010, 3)
        m["Ia"], m["Ib"], m["Ic"] = self._r(ia), self._r(ib), self._r(ic)

        m["Frequency"] = self._r(self.read_float_register(slave_id, 0x1018))

        pf_a, pf_b, pf_c, pf_avg = self.read_float_block(slave_id, 0x101C, 4)
        m["PF_A"],  m["PF_B"],  m["PF_C"] = self._r(pf_a), self._r(pf_b), self._r(pf_c)
        m["PF_avg"]                        = self._r(pf_avg)

    def poll_device(self, device: Dict[str, Any]) -> Dict[str, Any]:
        """輪詢 CPM-10B 設備"""
        slave_id = device['slave_id']
        result = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "device": device['name'],
            "slave_id": slave_id,
            "measurements": {}
        }

        logger.debug(f"Polling {device['name']} (ID: {slave_id})...")

        m = result["measurements"]

        # Va/Vb/Vc + Vab/Vbc/Vca + Ia/Ib/Ic + Freq + PF（1 或多次 RTU 請求）
        if self._use_mega_block:
            if not self._poll_mega(slave_id, m):
                logger.warning(f"Slave {slave_id}: mega block failed, falling back to split reads")
                self._use_mega_block = False
                self._poll_split(slave_id, m)
        else:
            self._poll_split(slave_id, m)

        # P_total + Q_total（1 次 RTU 請求，0x1032 起讀 5 floats）
        pwr = self.read_float_block(slave_id, _POWER_ADDR, _POWER_COUNT)
        m["P_total"] = self._r(pwr[0])
        m["Q_total"] = self._r(pwr[4])  # index 4 = 0x103A

        return result
