"""
存儲管理器 - 統一管理多種存儲方式
"""
import logging
from typing import Dict, Any, List
from .base import BaseStorage
from .csv_storage import CSVStorage
from .sqlite_storage import SQLiteStorage

logger = logging.getLogger(__name__)


class StorageManager:
    """存儲管理器 - 統一管理多種存儲方式"""
    
    def __init__(self, config: Dict[str, Any]):
        self.storages: List[BaseStorage] = []
        
        if not config.get('enabled', False):
            logger.info("Storage is disabled")
            return
        
        storage_types = config.get('types', [])
        
        # 初始化 CSV 存儲
        if 'csv' in storage_types:
            csv_dir = config.get('csv_directory', 'data/csv')
            self.storages.append(CSVStorage(csv_dir))
        
        # 初始化 SQLite 存儲
        if 'sqlite' in storage_types:
            sqlite_path = config.get('sqlite_path', 'data/modbus_data.db')
            self.storages.append(SQLiteStorage(sqlite_path))
        
        logger.info(f"Storage Manager initialized with {len(self.storages)} storage(s)")
    
    def save(self, data: Dict[str, Any]):
        """保存數據到所有啟用的存儲"""
        for storage in self.storages:
            storage.save(data)
    
    def close(self):
        """關閉所有存儲"""
        for storage in self.storages:
            storage.close()
