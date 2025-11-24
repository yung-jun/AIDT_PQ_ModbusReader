"""
存儲基類 - 定義存儲接口
"""
from abc import ABC, abstractmethod
from typing import Dict, Any


class BaseStorage(ABC):
    """存儲基類"""
    
    @abstractmethod
    def save(self, data: Dict[str, Any]):
        """保存數據"""
        pass
    
    @abstractmethod
    def close(self):
        """關閉存儲"""
        pass
