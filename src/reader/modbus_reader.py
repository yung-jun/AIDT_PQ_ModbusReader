"""
Modbus 讀取器基類
"""
import json
import logging
import struct
from abc import ABC, abstractmethod
from typing import Dict, List, Any, Optional
from pymodbus.client import ModbusSerialClient
from pymodbus.exceptions import ModbusException
from pymodbus.pdu import ExceptionResponse

logger = logging.getLogger(__name__)


class ModbusReader(ABC):
    """Modbus 讀取器基類"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.client = None
        self.setup_client()
    
    def setup_client(self):
        """設定 Modbus Client"""
        try:
            self.client = ModbusSerialClient(
                port=self.config['serial_port'],
                baudrate=self.config['baudrate'],
                parity=self.config['parity'],
                stopbits=self.config['stopbits'],
                bytesize=self.config['databits'],
                timeout=self.config['timeout_sec'],
                retries=1,
                reconnect_delay=0.1,
                reconnect_delay_max=1.0,
            )
        except Exception as e:
            logger.error(f"Failed to setup Modbus client: {e}")
            raise
    
    def connect(self) -> bool:
        """連接到 Modbus 設備"""
        try:
            if self.client.connect():
                logger.info(f"Connected to {self.config['serial_port']}")
                return True
            else:
                logger.error(f"Failed to connect to {self.config['serial_port']}")
                return False
        except Exception as e:
            logger.error(f"Connection error: {e}")
            return False
    
    def disconnect(self):
        """斷開連接"""
        if self.client:
            self.client.close()
            logger.info("Connection closed.")
    
    def decode_float(self, registers: List[int]) -> float:
        """
        將 2 個 16-bit 暫存器 (Modbus word) 轉換為 32-bit Float。
        使用 Big-Endian (ABCD) 格式。
        """
        raw_bytes = struct.pack('>HH', registers[0], registers[1])
        return struct.unpack('>f', raw_bytes)[0]
    
    def read_float_register(self, slave_id: int, start_address: int) -> Optional[float]:
        """讀取 2 個 Register 並轉為 Float"""
        try:
            rr = self.client.read_holding_registers(
                address=start_address,
                count=2,
                device_id=slave_id
            )

            if rr.isError():
                logger.warning(f"Modbus Error reading Addr {hex(start_address)} from Slave {slave_id}")
                return None

            if isinstance(rr, ExceptionResponse):
                logger.warning(f"Exception Response from Slave {slave_id}: {rr}")
                return None

            return self.decode_float(rr.registers)

        except ModbusException as e:
            logger.error(f"Modbus Exception on Slave {slave_id}: {e}")
            return None
        except Exception as e:
            logger.error(f"General Error: {e}")
            return None

    def read_float_block(self, slave_id: int, start_address: int, float_count: int) -> List[Optional[float]]:
        """一次 RTU 請求讀取多個連續 Float32 暫存器"""
        try:
            rr = self.client.read_holding_registers(
                address=start_address,
                count=float_count * 2,
                device_id=slave_id
            )

            if rr.isError() or isinstance(rr, ExceptionResponse):
                logger.warning(f"Block read error Addr {hex(start_address)} count={float_count} Slave {slave_id}")
                return [None] * float_count

            return [
                self.decode_float(rr.registers[i * 2:(i + 1) * 2])
                for i in range(float_count)
            ]

        except ModbusException as e:
            logger.error(f"Modbus Exception on Slave {slave_id}: {e}")
            return [None] * float_count
        except Exception as e:
            logger.error(f"General Error: {e}")
            return [None] * float_count
    
    @abstractmethod
    def get_register_map(self) -> List[Dict[str, Any]]:
        """獲取寄存器映射表 - 子類必須實現"""
        pass
    
    @abstractmethod
    def poll_device(self, device: Dict[str, Any]) -> Dict[str, Any]:
        """輪詢設備 - 子類必須實現"""
        pass
