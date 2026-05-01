"""
CSV 存儲實現 - 支援合併多設備數據為單行
"""
import csv
import logging
from datetime import datetime
from typing import Dict, Any, List
from pathlib import Path
from .base import BaseStorage

logger = logging.getLogger(__name__)


class CSVStorage(BaseStorage):
    """CSV 格式數據存儲 - 合併多設備為單行"""
    
    # 定義測量參數列表
    MEASUREMENT_FIELDS = [
        'Va', 'Vb', 'Vc',
        'Vab', 'Vbc', 'Vca',
        'Ia', 'Ib', 'Ic',
        'Frequency',
        'PF_A', 'PF_B', 'PF_C', 'PF_avg',
        'P_total', 'Q_total',
    ]
    
    def __init__(self, directory: str = "data/csv"):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.headers_written = False
        self.current_date = None
        self.filename = None
        self._update_filename()
        
        logger.info(f"CSV Storage initialized: {self.filename}")
    
    def _update_filename(self):
        """更新文件名（按日期分檔）"""
        today = datetime.now().strftime("%Y%m%d")
        if self.current_date != today:
            self.current_date = today
            self.filename = self.directory / f"modbus_data_{today}.csv"
            # 檢查文件是否已存在,如果存在則表示已有標題
            self.headers_written = self.filename.exists()
    
    def _generate_headers(self, devices_data: List[Dict[str, Any]]) -> List[str]:
        """生成 CSV 標題行（Meter_1_Va, Meter_1_Vb, ..., Meter_2_Va, ...）"""
        headers = ['timestamp']
        
        for data in devices_data:
            device_name = data['device']
            for field in self.MEASUREMENT_FIELDS:
                headers.append(f"{device_name}_{field}")
        
        return headers
    
    def save(self, data: Dict[str, Any]):
        """舊的單設備保存方法（保留向後兼容）"""
        self.save_combined([data])
    
    def save_combined(self, devices_data: List[Dict[str, Any]]):
        """保存合併的多設備數據到 CSV（單行）"""
        if not devices_data:
            return
        
        try:
            # 檢查是否需要更新文件名（跨日）
            self._update_filename()
            
            # 準備 CSV 標題
            headers = self._generate_headers(devices_data)
            
            # 準備數據行
            row = {'timestamp': devices_data[0]['timestamp']}
            
            for data in devices_data:
                device_name = data['device']
                measurements = data.get('measurements', {})
                
                for field in self.MEASUREMENT_FIELDS:
                    key = f"{device_name}_{field}"
                    row[key] = measurements.get(field, 0.0)
            
            # 打開文件(追加模式)
            mode = 'a' if self.headers_written else 'w'
            with open(self.filename, mode, newline='', encoding='utf-8') as f:
                writer = csv.DictWriter(f, fieldnames=headers)
                
                # 如果是第一次寫入,先寫標題
                if not self.headers_written:
                    writer.writeheader()
                    self.headers_written = True
                
                # 寫入數據行
                writer.writerow(row)
            
            device_names = [d['device'] for d in devices_data]
            logger.debug(f"Combined data saved to CSV: {device_names}")
            
        except Exception as e:
            logger.error(f"Failed to save data to CSV: {e}")
    
    def close(self):
        """關閉存儲(CSV 不需要特別關閉)"""
        logger.info("CSV Storage closed")
