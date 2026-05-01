"""
存儲基類 - 定義存儲接口
"""
from abc import ABC, abstractmethod
from typing import Dict, Any, List


class BaseStorage(ABC):
    """存儲基類"""
    
    @abstractmethod
    def save(self, data: Dict[str, Any]):
        """保存單一設備數據"""
        pass
    
    @abstractmethod
    def save_combined(self, devices_data: List[Dict[str, Any]]):
        """保存合併的多設備數據（單行格式）"""
        pass
    
    @abstractmethod
    def close(self):
        """關閉存儲"""
        pass

