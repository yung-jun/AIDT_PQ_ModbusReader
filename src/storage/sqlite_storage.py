"""
SQLite 存儲實現
"""
import sqlite3
import logging
from typing import Dict, Any, List
from pathlib import Path
from .base import BaseStorage

logger = logging.getLogger(__name__)


class SQLiteStorage(BaseStorage):
    """SQLite 數據庫存儲"""
    
    def __init__(self, db_path: str = "data/modbus_data.db"):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        self.conn = sqlite3.connect(str(self.db_path), check_same_thread=False)
        self.cursor = self.conn.cursor()
        
        self._create_tables()
        logger.info(f"SQLite Storage initialized: {self.db_path}")
    
    def _create_tables(self):
        """創建數據表"""
        # 創建測量數據表
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS measurements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                device_name TEXT NOT NULL,
                slave_id INTEGER NOT NULL,
                parameter_name TEXT NOT NULL,
                value REAL,
                unit TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # 創建索引以提升查詢性能
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON measurements(timestamp)
        ''')
        
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_device 
            ON measurements(device_name)
        ''')
        
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_parameter 
            ON measurements(parameter_name)
        ''')
        
        self.conn.commit()
    
    def save(self, data: Dict[str, Any]):
        """保存數據到 SQLite"""
        try:
            timestamp = data['timestamp']
            device_name = data['device']
            slave_id = data['slave_id']
            
            # 插入每個測量值
            for param_name, value in data['measurements'].items():
                # 從 register_map 獲取單位(這裡簡化處理,實際可以傳入)
                unit = self._get_unit_for_param(param_name)
                
                self.cursor.execute('''
                    INSERT INTO measurements 
                    (timestamp, device_name, slave_id, parameter_name, value, unit)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (timestamp, device_name, slave_id, param_name, value, unit))
            
            self.conn.commit()
            logger.debug(f"Data saved to SQLite: {device_name}")
            
        except Exception as e:
            logger.error(f"Failed to save data to SQLite: {e}")
            self.conn.rollback()
    
    def _get_unit_for_param(self, param_name: str) -> str:
        """根據參數名稱返回單位"""
        unit_map = {
            'Va': 'V', 'Vb': 'V', 'Vc': 'V',
            'Ia': 'A', 'Ib': 'A', 'Ic': 'A',
            'P_total': 'W',
            'Frequency': 'Hz',
            'Energy_Total': 'kWh'
        }
        return unit_map.get(param_name, '')
    
    def query_latest(self, device_name: str = None, limit: int = 10) -> List[Dict]:
        """查詢最新數據"""
        try:
            if device_name:
                self.cursor.execute('''
                    SELECT * FROM measurements 
                    WHERE device_name = ?
                    ORDER BY created_at DESC 
                    LIMIT ?
                ''', (device_name, limit))
            else:
                self.cursor.execute('''
                    SELECT * FROM measurements 
                    ORDER BY created_at DESC 
                    LIMIT ?
                ''', (limit,))
            
            columns = [desc[0] for desc in self.cursor.description]
            results = []
            for row in self.cursor.fetchall():
                results.append(dict(zip(columns, row)))
            
            return results
            
        except Exception as e:
            logger.error(f"Failed to query data: {e}")
            return []
    
    def close(self):
        """關閉數據庫連接"""
        if self.conn:
            self.conn.close()
            logger.info("SQLite Storage closed")
