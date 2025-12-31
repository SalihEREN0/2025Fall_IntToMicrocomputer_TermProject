import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import serial
import serial.tools.list_ports
import time
from abc import ABC, abstractmethod

# ==============================================================================
# 1. API LAYER 
# ==============================================================================

class HomeAutomationSystemConnection(ABC):
    """
    Abstract Base Class for handling serial connections to different automation boards.
    """
    def __init__(self):
        self.comPort = 0
        self.baudRate = 9600
        self.ser = None

    def setComPort(self, port: int):
        self.comPort = port

    def setBaudRate(self, rate: int):
        self.baudRate = rate

    def open(self) -> bool:
        """Attempts to open the serial connection with specified settings."""
        try:
            port_name = f"COM{self.comPort}"
            # Timeout increased based on requirement R2.3-2
            self.ser = serial.Serial(port_name, self.baudRate, timeout=0.5)
            # Stable settings derived from previous board2ui.py configurations
            self.ser.dtr = False
            self.ser.rts = False
            self.ser.flushInput()   # Clear buffer on startup to remove stale data
            self.ser.flushOutput()
            return True
        except Exception as e:
            print(f"Connection Error ({port_name}): {e}")
            return False

    def close(self) -> bool:
        """Safely closes the serial connection."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            return True
        return False

    def is_connected(self) -> bool:
        """Checks if the serial port is currently open."""
        return self.ser is not None and self.ser.is_open

    def _send_command(self, cmd_byte) -> int:
        """
        FIX: Send and Wait for Response (Smart Read).
        Old code just slept and read; this waits until data actually arrives.
        """
        if not self.is_connected(): return 0
        
        try:
            # Clear old (delayed) data from the buffer so synchronization doesn't drift
            self.ser.reset_input_buffer() 
            
            # Send the command byte
            self.ser.write(bytes([cmd_byte]))
            
            # Wait for response (Max 1.0 second)
            # Sensors like BMP180 read via I2C might delay the PIC's response.
            start_time = time.time()
            while (time.time() - start_time) < 1.0:
                if self.ser.in_waiting > 0:
                    data = self.ser.read(1)
                    return int.from_bytes(data, byteorder='big')
                time.sleep(0.01) # Tiny sleep to reduce CPU usage
            
            print(f"Timeout: No response for command {hex(cmd_byte)}.")
            return 0 # Return 0 on Timeout
        except Exception as e:
            print(f"IO Error: {e}")
            return 0

    @abstractmethod
    def update(self): 
        """Abstract method to update sensor data from the board."""
        pass


class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    """
    Concrete implementation for the Air Conditioner control board.
    """
    def __init__(self):
        super().__init__()
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def update(self):
        """Fetches current status from the AC unit via Serial."""
        if not self.is_connected(): return
        
        # 1. Get Desired Temp (Fractional part then Integer part)
        d_frac = self._send_command(0x01)
        d_int = self._send_command(0x02)
        self.desiredTemperature = float(f"{d_int}.{d_frac}")

        # 2. Get Ambient Temp (Fractional part then Integer part)
        a_frac = self._send_command(0x03)
        a_int = self._send_command(0x04)
        self.ambientTemperature = float(f"{a_int}.{a_frac}")

        # 3. Get Fan Speed
        self.fanSpeed = self._send_command(0x05)

    def setDesiredTemp(self, temp: float) -> bool:
        """Encodes and sends the target temperature to the microcontroller."""
        if not self.is_connected(): return False
        try:
            val_int = int(temp)
            val_frac = int((temp - val_int) * 10)
            if val_frac > 63: val_frac = 63

            # Protocol specific bitwise operations to form command bytes
            cmd_frac = 0x80 | (val_frac & 0x3F)
            cmd_int = 0xC0 | (val_int & 0x3F)

            self.ser.write(bytes([cmd_frac]))
            time.sleep(0.05) # Brief pause between bytes
            self.ser.write(bytes([cmd_int]))
            return True
        except: return False

    def getAmbientTemp(self): return self.ambientTemperature
    def getDesiredTemp(self): return self.desiredTemperature
    def getFanSpeed(self): return self.fanSpeed


class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    """
    Concrete implementation for the Curtain and Light control board.
    """
    # Commands defined in board2.asm firmware
    CMD_GET_CURTAIN = 0x02  # Ask Curtain Status
    CMD_GET_LIGHT = 0x08    # Ask Light Intensity
    
    def __init__(self):
        super().__init__()
        self.curtainStatus = 0.0
        self.outdoorTemperature = 25.0  # Static value (no command in board2.asm)
        self.outdoorPressure = 1013.0   # Static value (no command in board2.asm)
        self.lightIntensity = 0.0

    def _read_single_byte(self, cmd_byte) -> int:
        """
        board2ui.py style: Send single byte, receive single byte.
        """
        if not self.is_connected(): return 0
        
        try:
            self.ser.reset_input_buffer()
            self.ser.write(bytes([cmd_byte]))
            time.sleep(0.15)  # Allow time for PIC to process and respond
            
            # Wait for data to arrive (max 0.5 seconds)
            start_time = time.time()
            while (time.time() - start_time) < 0.5:
                if self.ser.in_waiting > 0:
                    raw_byte = self.ser.read(1)
                    int_val = int.from_bytes(raw_byte, byteorder='big')
                    print(f"<< Command {hex(cmd_byte)} -> Raw: {raw_byte} -> Int: {int_val}")
                    return int_val
                time.sleep(0.01)
            
            print(f"Timeout: No response for command {hex(cmd_byte)}.")
            return 0
        except Exception as e:
            print(f"IO Error: {e}")
            return 0

    def update(self):
        """
        Reading compatible with board2.asm firmware.
        Only 0x02 (curtain) and 0x08 (light) commands are available.
        Temp and Pressure are shown as static values.
        """
        if not self.is_connected(): return

        # 1. Curtain Status - Command: 0x02
        curtain_val = self._read_single_byte(self.CMD_GET_CURTAIN)
        self.curtainStatus = float(curtain_val)
        
        time.sleep(0.1)

        # 2. Light Intensity - Command: 0x08
        light_val = self._read_single_byte(self.CMD_GET_LIGHT)
        self.lightIntensity = float(light_val)
        
        # Temp and Pressure are not supported in board2.asm, keeping static
        # self.outdoorTemperature = 25.0
        # self.outdoorPressure = 1013.0
        
        # DEBUG: Check values in console
        print(f"[DEBUG] Curtain: {self.curtainStatus}% | Light: {self.lightIntensity} Lux")

    def setCurtainStatus(self, std: float) -> bool:
        """
        board2ui.py style: Send single byte formatted as 0xC0 | val.
        """
        if not self.is_connected(): return False
        try:
            val = int(std)
            
            # Construct the command byte
            cmd = 0xC0 | (val & 0x3F)
            self.ser.write(bytes([cmd]))
            print(f">> Sent: {cmd} (Hex: {hex(cmd)})")
            return True
        except Exception as e:
            print(f"setCurtainStatus Error: {e}")
            return False

    def getCurtainStatus(self): return self.curtainStatus
    def getOutdoorTemp(self): return self.outdoorTemperature
    def getOutdoorPress(self): return self.outdoorPressure
    def getLightIntensity(self): return self.lightIntensity


# ==============================================================================
# 2. INTERFACE LAYER (GUI)
# ==============================================================================

class HomeAutomationApp(tk.Tk):
    """
    Main GUI Application class using Tkinter.
    """
    def __init__(self):
        super().__init__()
        self.title("ESOGU Home Automation System (Robust)")
        self.geometry("600x550")
        self.resizable(False, False)
        
        # Initialize API instances
        self.ac_api = AirConditionerSystemConnection()
        self.curtain_api = CurtainControlSystemConnection()
        
        self.container = tk.Frame(self)
        self.container.pack(fill="both", expand=True, padx=20, pady=20)
        
        self.show_main_menu()
        
        # Update Rate: 2 seconds is ideal for sensors to catch up (Per documentation)
        self.update_interval = 2000 
        self.update_data_loop()

    def clear_screen(self):
        """Removes all widgets from the current view."""
        for widget in self.container.winfo_children():
            widget.destroy()

    def ask_port_connection(self, api_obj, system_name):
        """Creates a popup window to select and connect to a COM port."""
        popup = tk.Toplevel(self)
        popup.title(f"Connect {system_name}")
        popup.geometry("300x150")
        
        tk.Label(popup, text=f"Port for {system_name}:").pack(pady=5)
        # List available ports or default to COM1-9
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports: ports = [f"COM{i}" for i in range(1, 10)]
        
        combo = ttk.Combobox(popup, values=ports)
        if ports: combo.current(0)
        combo.pack(pady=5)

        def connect():
            p = combo.get()
            try:
                p_num = int(p.upper().replace("COM", ""))
                api_obj.setComPort(p_num)
                if api_obj.open():
                    messagebox.showinfo("OK", f"Connected {p}")
                    popup.destroy()
                else: messagebox.showerror("Err", "Failed")
            except: pass
        
        tk.Button(popup, text="Connect", command=connect).pack(pady=10)
        self.wait_window(popup)

    def show_main_menu(self):
        """Displays the main navigation menu."""
        self.clear_screen()
        frame = tk.LabelFrame(self.container, text="MAIN MENU", font=("Arial", 14, "bold"), padx=20, pady=20)
        frame.pack(expand=True)
        tk.Button(frame, text="1. Air Conditioner", width=25, command=self.on_ac).pack(pady=5)
        tk.Button(frame, text="2. Curtain Control", width=25, command=self.on_cc).pack(pady=5)
        tk.Button(frame, text="3. Exit", width=25, bg="red", fg="white", command=self.quit_app).pack(pady=5)

    def on_ac(self):
        """Handler for Air Conditioner button."""
        if not self.ac_api.is_connected(): self.ask_port_connection(self.ac_api, "Air Conditioner")
        if self.ac_api.is_connected(): self.show_ac()

    def on_cc(self):
        """Handler for Curtain Control button."""
        if not self.curtain_api.is_connected(): self.ask_port_connection(self.curtain_api, "Curtain")
        if self.curtain_api.is_connected(): self.show_cc()

    def show_ac(self):
        """Displays the Air Conditioner Monitor/Control interface."""
        self.clear_screen()
        f_info = tk.LabelFrame(self.container, text="Monitor", font=("Arial", 10, "bold"))
        f_info.pack(fill="x", pady=10)
        
        self.lbl_ac1 = tk.Label(f_info, text="Amb: --", font=("Arial", 12))
        self.lbl_ac1.pack(anchor="w", padx=10)
        self.lbl_ac2 = tk.Label(f_info, text="Des: --", font=("Arial", 12))
        self.lbl_ac2.pack(anchor="w", padx=10)
        self.lbl_ac3 = tk.Label(f_info, text="Fan: --", font=("Arial", 12))
        self.lbl_ac3.pack(anchor="w", padx=10)

        tk.Button(self.container, text="Set Temp", command=self.set_temp).pack(fill="x", pady=5)
        tk.Button(self.container, text="Return", command=self.show_main_menu).pack(fill="x", pady=5)

    def set_temp(self):
        """Dialog to input desired temperature."""
        val = simpledialog.askfloat("Input", "Temp (10-50):", minvalue=10, maxvalue=50)
        if val: self.ac_api.setDesiredTemp(val)

    def show_cc(self):
        """Displays the Curtain & Light Monitor/Control interface."""
        self.clear_screen()
        f_info = tk.LabelFrame(self.container, text="System Monitor", font=("Arial", 10, "bold"))
        f_info.pack(fill="x", pady=10)
        
        self.lbl_cc1 = tk.Label(f_info, text="Outdoor Temp: --", font=("Arial", 11))
        self.lbl_cc1.pack(anchor="w", padx=10)
        self.lbl_cc2 = tk.Label(f_info, text="Pressure: --", font=("Arial", 11))
        self.lbl_cc2.pack(anchor="w", padx=10)
        self.lbl_cc3 = tk.Label(f_info, text="Curtain: --", font=("Arial", 11, "bold"), fg="blue")
        self.lbl_cc3.pack(anchor="w", padx=10)
        self.lbl_cc4 = tk.Label(f_info, text="Light: --", font=("Arial", 11))
        self.lbl_cc4.pack(anchor="w", padx=10)

        tk.Button(self.container, text="Set Curtain", command=self.set_curtain).pack(fill="x", pady=5)
        tk.Button(self.container, text="Return", command=self.show_main_menu).pack(fill="x", pady=5)

    def set_curtain(self):
        """Dialog to input curtain opening percentage."""
        val = simpledialog.askfloat("Input", "Curtain %:")
        if val is not None: self.curtain_api.setCurtainStatus(val)

    def update_data_loop(self):
        """
        Periodic loop to fetch data from hardware and update UI labels.
        """
        if self.ac_api.is_connected(): self.ac_api.update()
        if self.curtain_api.is_connected(): self.curtain_api.update()

        try:
            # Update AC labels if they exist
            if hasattr(self, 'lbl_ac1') and self.lbl_ac1.winfo_exists():
                self.lbl_ac1.config(text=f"Home Ambient Temperature: {self.ac_api.getAmbientTemp():.1f} C")
                self.lbl_ac2.config(text=f"Home Desired Temperature: {self.ac_api.getDesiredTemp():.1f} C")
                self.lbl_ac3.config(text=f"Fan Speed: {self.ac_api.getFanSpeed()} rps")

            # Update Curtain labels if they exist
            if hasattr(self, 'lbl_cc1') and self.lbl_cc1.winfo_exists():
                self.lbl_cc1.config(text=f"Outdoor Temperature: {self.curtain_api.getOutdoorTemp():.1f} C")
                self.lbl_cc2.config(text=f"Outdoor Pressure: {self.curtain_api.getOutdoorPress():.0f} hPa")
                self.lbl_cc3.config(text=f"Curtain Status: {self.curtain_api.getCurtainStatus():.0f} %")
                self.lbl_cc4.config(text=f"Light Intensity: {self.curtain_api.getLightIntensity():.0f} Lux")
        except: pass
        
        # Schedule next update
        self.after(self.update_interval, self.update_data_loop)

    def quit_app(self):
        """Closes connections and destroys the window."""
        self.ac_api.close()
        self.curtain_api.close()
        self.destroy()

if __name__ == "__main__":
    app = HomeAutomationApp()
    app.mainloop()