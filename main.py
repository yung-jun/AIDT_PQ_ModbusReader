"""
CPM-10B Modbus Reader - 主程序入口點
"""
import json
import time
import logging
from src.utils import load_config, setup_logging
from src.reader import CPM10BReader
from src.storage import StorageManager

# 設置日誌
setup_logging()
logger = logging.getLogger(__name__)


def main():
    """主函數"""
    try:
        # 載入配置
        config = load_config("config.json")
        
        # 創建讀取器
        reader = CPM10BReader(config)
        
        # 初始化存儲管理器
        storage_config = config.get('storage', {'enabled': False})
        storage_manager = StorageManager(storage_config)
        
        # 連接設備
        if not reader.connect():
            logger.error("Failed to connect to Modbus device")
            return
        
        try:
            # 主循環
            while True:
                start_time = time.time()
                
                # 輪詢所有設備
                for device in config['devices']:
                    data = reader.poll_device(device)
                    
                    # 在 Console 印出漂亮的 JSON
                    print(json.dumps(data, indent=2))
                    
                    # 保存數據到存儲
                    storage_manager.save(data)
                
                # 計算等待時間
                elapsed = time.time() - start_time
                sleep_time = max(0, config['poll_interval_sec'] - elapsed)
                time.sleep(sleep_time)
        
        except KeyboardInterrupt:
            logger.info("Stopping CPM-10B Reader...")
        
        finally:
            # 清理資源
            storage_manager.close()
            reader.disconnect()
    
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
