"""
存儲管理器 - CSV 存儲管理
"""
import logging
from typing import Dict, Any, List
from .base import BaseStorage
from .csv_storage import CSVStorage

logger = logging.getLogger(__name__)


class StorageManager:
    """存儲管理器 - CSV 存儲管理"""
    
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
        
        logger.info(f"Storage Manager initialized with {len(self.storages)} storage(s)")
    
    def save(self, data: Dict[str, Any]):
        """保存單一設備數據到所有啟用的存儲（向後兼容）"""
        for storage in self.storages:
            storage.save(data)
    
    def save_combined(self, devices_data: List[Dict[str, Any]]):
        """保存合併的多設備數據到所有啟用的存儲（單行格式）"""
        for storage in self.storages:
            storage.save_combined(devices_data)
    
    def close(self):
        """關閉所有存儲"""
        for storage in self.storages:
            storage.close()
