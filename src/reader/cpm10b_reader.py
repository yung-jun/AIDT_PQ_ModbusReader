"""
CPM-10B 電力品質分析儀讀取器
"""
import time
import logging
from typing import Dict, List, Any
from .modbus_reader import ModbusReader

logger = logging.getLogger(__name__)


class CPM10BReader(ModbusReader):
    """CPM-10B 專用讀取器"""
    
    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self.register_map = self.get_register_map()
    
    def get_register_map(self) -> List[Dict[str, Any]]:
        """
        根據 CPM-10B Register List (PDF P.28) 建立對照表
        資料格式皆為 Float32 (2 Words / 4 Bytes)
        """
        return [
            # --- 電壓 (Voltage) ---
            {"name": "Va", "address": 0x1000, "unit": "V"},
            {"name": "Vb", "address": 0x1002, "unit": "V"},
            {"name": "Vc", "address": 0x1004, "unit": "V"},
            
            # --- 電流 (Current) ---
            {"name": "Ia", "address": 0x1010, "unit": "A"},
            {"name": "Ib", "address": 0x1012, "unit": "A"},
            {"name": "Ic", "address": 0x1014, "unit": "A"},
            
            # --- 功率 (Power) ---
            # Total Active Power (P.TL) - Address 1032H
            {"name": "P_total", "address": 0x1032, "unit": "W"},
            
            # --- 頻率 (Frequency) ---
            # Address 101AH
            {"name": "Frequency", "address": 0x101A, "unit": "Hz"},

            # --- 電能 (Energy) ---
            # Total Active Energy (AE.TL) - Address 1408H (PDF P.29)
            {"name": "Energy_Total", "address": 0x1408, "unit": "kWh"},
        ]
    
    def poll_device(self, device: Dict[str, Any]) -> Dict[str, Any]:
        """輪詢 CPM-10B 設備"""
        slave_id = device['slave_id']
        result = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "device": device['name'],
            "slave_id": slave_id,
            "measurements": {}
        }
        
        logger.info(f"Polling {device['name']} (ID: {slave_id})...")

        for reg in self.register_map:
            val = self.read_float_register(slave_id, reg['address'])
            
            if val is not None:
                # 取小數點後 3 位
                result["measurements"][reg["name"]] = round(val, 3)
            else:
                result["measurements"][reg["name"]] = None
                
            # 避免讀取太快,稍微 delay (可選)
            time.sleep(0.05)
        
        return result
