import serial
import time
import tkinter as tk
from tkinter import ttk, messagebox
import threading

# ==============================================================================
# CLASS: Air Conditioner System API
# (Serial Communication Logic - Unchanged, kept as is)
# ==============================================================================
class AirConditionerSystemConnection:
    def __init__(self):
        self.ser = None
        self.comPort = "COM1"  # Adjust the port according to your system
        self.baudRate = 9600
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def setComPort(self, port):
        self.comPort = port

    def setBaudRate(self, rate):
        self.baudRate = rate

    def open(self):
        try:
            self.ser = serial.Serial(self.comPort, self.baudRate, timeout=0.1)
            return True
        except Exception as e:
            print(f"Connection Error: {e}")
            return False

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()

    def _send_byte(self, byte_val):
        if self.ser and self.ser.is_open:
            self.ser.write(bytes([byte_val]))

    def _read_byte(self):
        if self.ser and self.ser.is_open:
            data = self.ser.read(1)
            if data:
                return int.from_bytes(data, byteorder='big')
        return 0

    def update(self):
        try:
            # 1. Desired Temp (Frac & Int)
            self._send_byte(0x01)
            d_frac = self._read_byte()
            self._send_byte(0x02)
            d_int = self._read_byte()
            self.desiredTemperature = float(f"{d_int}.{d_frac}")

            # 2. Ambient Temp (Frac & Int)
            self._send_byte(0x03)
            a_frac = self._read_byte()
            self._send_byte(0x04)
            a_int = self._read_byte()
            self.ambientTemperature = float(f"{a_int}.{a_frac}")

            # 3. Fan Speed (Source 197 - Command 0x05)
            self._send_byte(0x05)
            self.fanSpeed = self._read_byte()
            return True
        except Exception as e:
            print(f"Update Error: {e}")
            return False

    def setDesiredTemp(self, temp: float):
        try:
            t_int = int(temp)
            t_frac = int((temp - t_int) * 100)
            if t_frac > 63: t_frac = 63 # 6-bit limit

            # Send Fraction: 10xxxxxx
            cmd_frac = 0x80 | (t_frac & 0x3F)
            self._send_byte(cmd_frac)
            time.sleep(0.05)

            # Send Integer: 11xxxxxx
            cmd_int = 0xC0 | (t_int & 0x3F)
            self._send_byte(cmd_int)
            return True
        except Exception as e:
            print(f"Set Temp Error: {e}")
            return False

    def getAmbientTemp(self): return self.ambientTemperature
    def getDesiredTemp(self): return self.desiredTemperature
    def getFanSpeed(self): return self.fanSpeed

# ==============================================================================
# GUI CLASS (Tkinter Interface)
# ==============================================================================
class HomeAutomationUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Home Automation - Air Conditioner Control")
        self.root.geometry("400x500")
        self.root.resizable(False, False)

        # API Object
        self.api = AirConditionerSystemConnection()
        self.is_connected = False

        # --- Style Settings ---
        style = ttk.Style()
        style.configure("TLabel", font=("Helvetica", 12))
        style.configure("TButton", font=("Helvetica", 10))
        style.configure("Header.TLabel", font=("Helvetica", 16, "bold"))

        # --- Connection Area ---
        conn_frame = ttk.LabelFrame(root, text="Connection Settings", padding=10)
        conn_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(conn_frame, text="COM Port:").grid(row=0, column=0, padx=5, pady=5)
        self.port_entry = ttk.Entry(conn_frame, width=10)
        self.port_entry.insert(0, "COM1") # Default
        self.port_entry.grid(row=0, column=1, padx=5, pady=5)

        self.btn_connect = ttk.Button(conn_frame, text="Connect", command=self.toggle_connection)
        self.btn_connect.grid(row=0, column=2, padx=5, pady=5)

        self.lbl_status = ttk.Label(conn_frame, text="Status: Disconnected", foreground="red")
        self.lbl_status.grid(row=1, column=0, columnspan=3, pady=5)

        # --- Data Display Area ---
        data_frame = ttk.LabelFrame(root, text="System Monitor", padding=20)
        data_frame.pack(fill="both", expand=True, padx=10, pady=10)

        # Ambient Temp
        ttk.Label(data_frame, text="Ambient Temp:", style="Header.TLabel").pack(pady=(10, 0))
        self.lbl_ambient = ttk.Label(data_frame, text="--.-- °C", font=("Helvetica", 24, "bold"), foreground="blue")
        self.lbl_ambient.pack(pady=(0, 10))

        # Desired Temp (Display)
        ttk.Label(data_frame, text="Desired Temp (Current):").pack()
        self.lbl_desired = ttk.Label(data_frame, text="--.-- °C", font=("Helvetica", 14))
        self.lbl_desired.pack(pady=(0, 10))

        # Fan Speed
        ttk.Label(data_frame, text="Fan Speed:").pack()
        self.lbl_fan = ttk.Label(data_frame, text="-- rps", font=("Helvetica", 14), foreground="green")
        self.lbl_fan.pack(pady=(0, 10))

        # --- Control Area ---
        ctrl_frame = ttk.LabelFrame(root, text="Control Panel", padding=10)
        ctrl_frame.pack(fill="x", padx=10, pady=10)

        ttk.Label(ctrl_frame, text="Set New Temp:").grid(row=0, column=0, padx=5)
        self.entry_set_temp = ttk.Entry(ctrl_frame, width=10)
        self.entry_set_temp.grid(row=0, column=1, padx=5)
        
        self.btn_set = ttk.Button(ctrl_frame, text="Set", command=self.send_temperature)
        self.btn_set.grid(row=0, column=2, padx=5)
        self.btn_set.config(state="disabled")

        # Start the loop
        self.update_interval = 1000 # 1 second
        self.update_gui()

    def toggle_connection(self):
        if not self.is_connected:
            port = self.port_entry.get()
            self.api.setComPort(port)
            if self.api.open():
                self.is_connected = True
                self.btn_connect.config(text="Disconnect")
                self.lbl_status.config(text=f"Status: Connected ({port})", foreground="green")
                self.btn_set.config(state="normal")
                print(f"[SYSTEM] Connected to {port}")
            else:
                messagebox.showerror("Error", f"Could not open {port}")
        else:
            self.api.close()
            self.is_connected = False
            self.btn_connect.config(text="Connect")
            self.lbl_status.config(text="Status: Disconnected", foreground="red")
            self.btn_set.config(state="disabled")
            print("[SYSTEM] Disconnected")

    def send_temperature(self):
        if not self.is_connected: return
        try:
            val = float(self.entry_set_temp.get())
            if 10.0 <= val <= 50.0:
                self.api.setDesiredTemp(val)
                print(f"[USER ACTION] Set Temperature to {val}")
                messagebox.showinfo("Success", f"Temperature set to {val}")
            else:
                messagebox.showwarning("Range Error", "Temperature must be between 10.0 and 50.0")
        except ValueError:
            messagebox.showerror("Format Error", "Please enter a valid number.")

    def update_gui(self):
        if self.is_connected:
            # 1. Update data from API
            success = self.api.update()
            
            if success:
                # 2. Update GUI Elements
                amb_temp = self.api.getAmbientTemp()
                des_temp = self.api.getDesiredTemp()
                fan_spd = self.api.getFanSpeed()

                self.lbl_ambient.config(text=f"{amb_temp:.2f} °C")
                self.lbl_desired.config(text=f"{des_temp:.2f} °C")
                self.lbl_fan.config(text=f"{fan_spd} rps")

                # 3. PRINT TO TERMINAL (As requested)
                print(f"--------------------------------------------------")
                print(f"[DATA] Ambient: {amb_temp:.2f} C | Desired: {des_temp:.2f} C | Fan: {fan_spd} rps")
        
        # Call itself again (Loop)
        self.root.after(self.update_interval, self.update_gui)

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================
if __name__ == "__main__":
    root = tk.Tk()
    app = HomeAutomationUI(root)
    
    # Print Info to Terminal
    print("==================================================")
    print("      HOME AUTOMATION - GUI & TERMINAL APP        ")
    print("==================================================")
    print("Launching UI... Check the window to connect.")
    
    root.mainloop()