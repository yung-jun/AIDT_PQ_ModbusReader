"""
CPM-10B Modbus Reader - 主程式入口
"""
import json
import time
import logging
from datetime import datetime
from .utils import load_config, setup_logging
from .reader import CPM10BReader
from .storage import StorageManager

# 設置logger
setup_logging()
logger = logging.getLogger(__name__)


def main():
    try:
        # 載入配置
        config = load_config("config.json")
        
        # 創建Reader
        reader = CPM10BReader(config)
        
        # 初始化存儲管理器
        storage_config = config.get('storage', {'enabled': False})
        storage_manager = StorageManager(storage_config)
        
        # 連接設備
        if not reader.connect():
            logger.error("Failed to connect to Modbus device")
            return
        
        try:
            cycle_count = 0
            while True:
                start_time = time.time()
                
                # 使用統一的時間戳記
                shared_timestamp = datetime.now().isoformat(timespec='milliseconds')
                
                # 收集所有設備的數據
                all_devices_data = []
                
                # 輪詢所有設備
                for device in config['devices']:
                    data = reader.poll_device(device)
                    
                    # 使用共享的時間戳記
                    data['timestamp'] = shared_timestamp
                    
                    print(json.dumps(data, indent=2))
                    all_devices_data.append(data)
                
                # 將所有設備數據合併成一行存儲
                if all_devices_data:
                    storage_manager.save_combined(all_devices_data)

                # serial I/O timeout 為 kernel blocking，不燒 CPU；
                # 0.1s 底限確保 SSH 不被 starvation，同時允許 ~5 Hz 取樣。
                elapsed = time.time() - start_time
                sleep_time = max(0.01, config['poll_interval_sec'] - elapsed)
                cycle_count += 1
                if cycle_count % 50 == 0:
                    logger.info(f"Cycle #{cycle_count}: read={elapsed*1000:.1f}ms  sleep={sleep_time*1000:.1f}ms  total={(elapsed+sleep_time)*1000:.1f}ms")
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
