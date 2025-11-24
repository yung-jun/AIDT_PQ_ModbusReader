"""
CSV 存儲實現
"""
import csv
import logging
from datetime import datetime
from typing import Dict, Any
from pathlib import Path
from .base import BaseStorage

logger = logging.getLogger(__name__)


class CSVStorage(BaseStorage):
    """CSV 格式數據存儲"""
    
    def __init__(self, directory: str = "data/csv"):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.current_file = None
        self.csv_writer = None
        self.file_handle = None
        self.headers_written = False
        
        # 創建帶日期的文件名
        date_str = datetime.now().strftime("%Y%m%d")
        self.filename = self.directory / f"modbus_data_{date_str}.csv"
        
        # 檢查文件是否已存在,如果存在則表示已有標題
        self.headers_written = self.filename.exists()
        
        logger.info(f"CSV Storage initialized: {self.filename}")
    
    def save(self, data: Dict[str, Any]):
        """保存數據到 CSV"""
        try:
            # 打開文件(追加模式)
            mode = 'a' if self.headers_written else 'w'
            with open(self.filename, mode, newline='', encoding='utf-8') as f:
                # 準備扁平化的數據行
                row = {
                    'timestamp': data['timestamp'],
                    'device': data['device'],
                    'slave_id': data['slave_id']
                }
                
                # 添加所有測量值
                for key, value in data['measurements'].items():
                    row[key] = value
                
                # 創建 CSV writer
                writer = csv.DictWriter(f, fieldnames=row.keys())
                
                # 如果是第一次寫入,先寫標題
                if not self.headers_written:
                    writer.writeheader()
                    self.headers_written = True
                
                # 寫入數據行
                writer.writerow(row)
                
            logger.debug(f"Data saved to CSV: {data['device']}")
            
        except Exception as e:
            logger.error(f"Failed to save data to CSV: {e}")
    
    def close(self):
        """關閉存儲(CSV 不需要特別關閉)"""
        logger.info("CSV Storage closed")
