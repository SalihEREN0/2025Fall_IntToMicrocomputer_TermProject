"""
PIC16F877A UART Protocol Configuration
Communication protocol for temperature control system
"""

import serial
from enum import IntEnum
from dataclasses import dataclass
from typing import Optional

# =============================================================================
# UART CONFIGURATION
# =============================================================================

UART_CONFIG = {
    'baudrate': 9600,
    'bytesize': serial.EIGHTBITS,
    'parity': serial.PARITY_NONE,
    'stopbits': serial.STOPBITS_ONE,
    'timeout': 1,
    'write_timeout': 1,
}

# Default COM ports (com0com virtual pair)
DEFAULT_PORT_UI = 'COM14'      # UI connects here
DEFAULT_PORT_PIC = 'COM15'     # PIC/Simulator connects here


# =============================================================================
# COMMAND DEFINITIONS (R2.1.4-1)
# =============================================================================

class Command(IntEnum):
    """UART Command bytes as per R2.1.4-1 specification"""
    
    # GET Commands (bit 7 = 0)
    GET_DESIRED_FRAC = 0x01     # 00000001B - Get desired temperature fractional part
    GET_DESIRED_INT = 0x02      # 00000010B - Get desired temperature integral part
    GET_AMBIENT_FRAC = 0x03     # 00000011B - Get ambient temperature fractional part
    GET_AMBIENT_INT = 0x04      # 00000100B - Get ambient temperature integral part
    GET_FAN_SPEED = 0x05        # 00000101B - Get fan speed (RPS)
    
    # SET Commands use bit patterns:
    # SET_DESIRED_FRAC: 10xxxxxx (0x80 | value)  - Set desired temp fraction
    # SET_DESIRED_INT:  11xxxxxx (0xC0 | value)  - Set desired temp integer


class CommandMask:
    """Bit masks for command encoding/decoding"""
    SET_FRAC_PREFIX = 0x80      # 10xxxxxx - Set fractional part
    SET_INT_PREFIX = 0xC0       # 11xxxxxx - Set integral part
    VALUE_MASK = 0x3F           # xxxxxx - 6-bit value mask (0-63)
    CMD_TYPE_MASK = 0xC0        # Top 2 bits determine command type


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class Temperature:
    """Temperature value with integer and fractional parts"""
    integer: int = 0        # 0-63 (6-bit)
    fraction: int = 0       # 0-99 (represents .00 to .99)
    
    def __str__(self) -> str:
        return f"{self.integer}.{self.fraction:02d}"
    
    def to_float(self) -> float:
        return self.integer + (self.fraction / 100.0)
    
    @classmethod
    def from_float(cls, value: float) -> 'Temperature':
        integer = int(value)
        fraction = int((value - integer) * 100)
        return cls(integer=integer, fraction=fraction)
    
    def is_valid(self) -> bool:
        """Check if temperature is in valid range (10.0 - 50.0)"""
        temp = self.to_float()
        return 10.0 <= temp <= 50.0


@dataclass
class SystemStatus:
    """Current system status"""
    desired_temp: Temperature = None
    ambient_temp: Temperature = None
    fan_speed: int = 0
    heater_on: bool = False
    cooler_on: bool = False
    connected: bool = False
    
    def __post_init__(self):
        if self.desired_temp is None:
            self.desired_temp = Temperature(27, 0)
        if self.ambient_temp is None:
            self.ambient_temp = Temperature(0, 0)


# =============================================================================
# PROTOCOL HELPER FUNCTIONS
# =============================================================================

def encode_set_desired_int(value: int) -> bytes:
    """Encode SET desired temperature integer command"""
    if not 0 <= value <= 63:
        raise ValueError(f"Value must be 0-63, got {value}")
    cmd = CommandMask.SET_INT_PREFIX | (value & CommandMask.VALUE_MASK)
    return bytes([cmd])


def encode_set_desired_frac(value: int) -> bytes:
    """Encode SET desired temperature fraction command"""
    if not 0 <= value <= 63:
        raise ValueError(f"Value must be 0-63, got {value}")
    cmd = CommandMask.SET_FRAC_PREFIX | (value & CommandMask.VALUE_MASK)
    return bytes([cmd])


def encode_get_command(cmd: Command) -> bytes:
    """Encode a GET command"""
    return bytes([cmd])


def decode_command_type(byte: int) -> str:
    """Decode command type from received byte"""
    if byte & 0x80 == 0:
        # GET command response
        return "GET_RESPONSE"
    elif byte & 0xC0 == 0xC0:
        return "SET_INT"
    elif byte & 0x80 == 0x80:
        return "SET_FRAC"
    return "UNKNOWN"


def decode_set_value(byte: int) -> int:
    """Extract 6-bit value from SET command"""
    return byte & CommandMask.VALUE_MASK


# =============================================================================
# SERIAL PORT MANAGER
# =============================================================================

class SerialManager:
    """Manages serial port connection"""
    
    def __init__(self, port: str = DEFAULT_PORT_UI):
        self.port = port
        self.serial: Optional[serial.Serial] = None
        self._is_connected = False
    
    @property
    def is_connected(self) -> bool:
        return self._is_connected and self.serial is not None and self.serial.is_open
    
    def connect(self, port: str = None) -> bool:
        """Connect to serial port"""
        if port:
            self.port = port
        
        try:
            self.serial = serial.Serial(port=self.port, **UART_CONFIG)
            self._is_connected = True
            return True
        except Exception as e:
            print(f"Connection error: {e}")
            self._is_connected = False
            return False
    
    def disconnect(self):
        """Disconnect from serial port"""
        if self.serial and self.serial.is_open:
            self.serial.close()
        self._is_connected = False
    
    def send(self, data: bytes) -> bool:
        """Send bytes over serial"""
        if not self.is_connected:
            return False
        try:
            self.serial.write(data)
            return True
        except Exception as e:
            print(f"Send error: {e}")
            return False
    
    def receive(self, count: int = 1) -> Optional[bytes]:
        """Receive bytes from serial"""
        if not self.is_connected:
            return None
        try:
            if self.serial.in_waiting >= count:
                return self.serial.read(count)
            return None
        except Exception as e:
            print(f"Receive error: {e}")
            return None
    
    def send_command(self, cmd: Command) -> bool:
        """Send a GET command"""
        return self.send(encode_get_command(cmd))
    
    def set_desired_temperature(self, temp: Temperature) -> bool:
        """Send SET commands to update desired temperature"""
        success = True
        success &= self.send(encode_set_desired_int(temp.integer))
        success &= self.send(encode_set_desired_frac(temp.fraction))
        return success
    
    @staticmethod
    def list_ports() -> list:
        """List available COM ports"""
        import serial.tools.list_ports
        return [port.device for port in serial.tools.list_ports.comports()]


# =============================================================================
# COMMAND TABLE (Documentation)
# =============================================================================
"""
UART PROTOCOL REFERENCE TABLE (R2.1.4-1)
=========================================

GET Commands (UI → PIC):
┌─────────────────────────────────┬────────────┬─────────────────────────┐
│ Command                         │ Byte       │ Description             │
├─────────────────────────────────┼────────────┼─────────────────────────┤
│ Get desired temp fraction       │ 0x01       │ Returns TARGET_TEMP_FRAC│
│ Get desired temp integer        │ 0x02       │ Returns TARGET_TEMP_INT │
│ Get ambient temp fraction       │ 0x03       │ Returns FRAC_TEMP       │
│ Get ambient temp integer        │ 0x04       │ Returns AMBIENT_TEMP    │
│ Get fan speed (RPS)             │ 0x05       │ Returns FAN_SPEED_STORE │
└─────────────────────────────────┴────────────┴─────────────────────────┘

SET Commands (UI → PIC):
┌─────────────────────────────────┬────────────┬─────────────────────────┐
│ Command                         │ Format     │ Description             │
├─────────────────────────────────┼────────────┼─────────────────────────┤
│ Set desired temp fraction       │ 10xxxxxx   │ x = 6-bit value (0-63)  │
│ Set desired temp integer        │ 11xxxxxx   │ x = 6-bit value (0-63)  │
└─────────────────────────────────┴────────────┴─────────────────────────┘

Response (PIC → UI):
- All GET commands return a single byte with the requested value
- SET commands do not return any response

Example:
- To set temperature to 27.50:
  1. Send 0xDB (0xC0 | 27) - Set integer to 27
  2. Send 0xB2 (0x80 | 50) - Set fraction to 50
  
- To read desired temperature:
  1. Send 0x02 - Request integer part
  2. Receive response (e.g., 0x1B = 27)
  3. Send 0x01 - Request fraction part  
  4. Receive response (e.g., 0x32 = 50)
  5. Temperature = 27.50°C
"""
