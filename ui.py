"""
PIC16F877A Temperature Control UI
Communicates via UART (9600 baud)
"""

import tkinter as tk
from tkinter import ttk, messagebox
import serial
import serial.tools.list_ports
import threading
import time
import re

class TemperatureControlUI:
    def __init__(self, root):
        self.root = root
        self.root.title("PIC16F877A Temperature Control")
        self.root.geometry("600x500")
        self.root.resizable(False, False)
        
        # Serial connection
        self.serial_port = None
        self.running = False
        self.read_thread = None
        
        # Data variables
        self.desired_temp = tk.StringVar(value="--.-")
        self.ambient_temp = tk.StringVar(value="--.-")
        self.fan_speed = tk.StringVar(value="---")
        self.heater_status = tk.StringVar(value="OFF")
        self.cooler_status = tk.StringVar(value="OFF")
        self.connection_status = tk.StringVar(value="Disconnected")
        
        self.create_widgets()
        self.refresh_ports()
        
    def create_widgets(self):
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky="nsew")
        
        # Connection Frame
        conn_frame = ttk.LabelFrame(main_frame, text="Connection", padding="10")
        conn_frame.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))
        
        ttk.Label(conn_frame, text="Port:").grid(row=0, column=0, padx=5)
        self.port_combo = ttk.Combobox(conn_frame, width=15, state="readonly")
        self.port_combo.grid(row=0, column=1, padx=5)
        
        ttk.Button(conn_frame, text="Refresh", command=self.refresh_ports).grid(row=0, column=2, padx=5)
        self.connect_btn = ttk.Button(conn_frame, text="Connect", command=self.toggle_connection)
        self.connect_btn.grid(row=0, column=3, padx=5)
        
        ttk.Label(conn_frame, textvariable=self.connection_status, foreground="red").grid(row=0, column=4, padx=20)
        
        # Temperatures Frame
        temp_frame = ttk.LabelFrame(main_frame, text="Temperatures", padding="20")
        temp_frame.grid(row=1, column=0, columnspan=2, sticky="ew", pady=10)
        
        # Desired Temperature
        ttk.Label(temp_frame, text="Desired Temperature:", font=("Arial", 12)).grid(row=0, column=0, sticky="w", pady=5)
        ttk.Label(temp_frame, textvariable=self.desired_temp, font=("Arial", 24, "bold"), foreground="blue").grid(row=0, column=1, padx=20)
        ttk.Label(temp_frame, text="°C", font=("Arial", 16)).grid(row=0, column=2)
        
        # Ambient Temperature
        ttk.Label(temp_frame, text="Ambient Temperature:", font=("Arial", 12)).grid(row=1, column=0, sticky="w", pady=5)
        ttk.Label(temp_frame, textvariable=self.ambient_temp, font=("Arial", 24, "bold"), foreground="green").grid(row=1, column=1, padx=20)
        ttk.Label(temp_frame, text="°C", font=("Arial", 16)).grid(row=1, column=2)
        
        # Fan Speed
        ttk.Label(temp_frame, text="Fan Speed:", font=("Arial", 12)).grid(row=2, column=0, sticky="w", pady=5)
        ttk.Label(temp_frame, textvariable=self.fan_speed, font=("Arial", 24, "bold"), foreground="orange").grid(row=2, column=1, padx=20)
        ttk.Label(temp_frame, text="RPS", font=("Arial", 16)).grid(row=2, column=2)
        
        # Status Frame
        status_frame = ttk.LabelFrame(main_frame, text="Device Status", padding="20")
        status_frame.grid(row=2, column=0, columnspan=2, sticky="ew", pady=10)
        
        # Heater Status
        ttk.Label(status_frame, text="Heater:", font=("Arial", 12)).grid(row=0, column=0, padx=20)
        self.heater_label = ttk.Label(status_frame, textvariable=self.heater_status, font=("Arial", 14, "bold"))
        self.heater_label.grid(row=0, column=1, padx=10)
        
        # Heater indicator
        self.heater_canvas = tk.Canvas(status_frame, width=30, height=30, highlightthickness=0)
        self.heater_canvas.grid(row=0, column=2)
        self.heater_indicator = self.heater_canvas.create_oval(5, 5, 25, 25, fill="gray")
        
        # Cooler Status
        ttk.Label(status_frame, text="Cooler/Fan:", font=("Arial", 12)).grid(row=0, column=3, padx=20)
        self.cooler_label = ttk.Label(status_frame, textvariable=self.cooler_status, font=("Arial", 14, "bold"))
        self.cooler_label.grid(row=0, column=4, padx=10)
        
        # Cooler indicator
        self.cooler_canvas = tk.Canvas(status_frame, width=30, height=30, highlightthickness=0)
        self.cooler_canvas.grid(row=0, column=5)
        self.cooler_indicator = self.cooler_canvas.create_oval(5, 5, 25, 25, fill="gray")
        
        # Set Temperature Frame
        set_frame = ttk.LabelFrame(main_frame, text="Set Desired Temperature", padding="20")
        set_frame.grid(row=3, column=0, columnspan=2, sticky="ew", pady=10)
        
        ttk.Label(set_frame, text="New Temperature:", font=("Arial", 12)).grid(row=0, column=0, padx=10)
        
        self.new_temp_entry = ttk.Entry(set_frame, width=10, font=("Arial", 14))
        self.new_temp_entry.grid(row=0, column=1, padx=10)
        self.new_temp_entry.insert(0, "27.0")
        
        ttk.Label(set_frame, text="°C (10.0 - 50.0)", font=("Arial", 10)).grid(row=0, column=2)
        
        self.set_btn = ttk.Button(set_frame, text="Set Temperature", command=self.set_temperature)
        self.set_btn.grid(row=0, column=3, padx=20)
        
        # Quick preset buttons
        preset_frame = ttk.Frame(set_frame)
        preset_frame.grid(row=1, column=0, columnspan=4, pady=10)
        
        ttk.Label(preset_frame, text="Presets:").pack(side=tk.LEFT, padx=5)
        for temp in [20, 25, 27, 30, 35]:
            ttk.Button(preset_frame, text=f"{temp}°C", width=6,
                      command=lambda t=temp: self.quick_set(t)).pack(side=tk.LEFT, padx=3)
        
        # Refresh button
        ttk.Button(preset_frame, text="🔄 Refresh", width=10,
                  command=self.poll_device_async).pack(side=tk.LEFT, padx=10)
        
        # Log Frame
        log_frame = ttk.LabelFrame(main_frame, text="Communication Log", padding="5")
        log_frame.grid(row=4, column=0, columnspan=2, sticky="ew", pady=10)
        
        self.log_text = tk.Text(log_frame, height=6, width=70, font=("Consolas", 9))
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        scrollbar = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.configure(yscrollcommand=scrollbar.set)
        
    def refresh_ports(self):
        """Refresh available COM ports"""
        ports = [port.device for port in serial.tools.list_ports.comports()]
        self.port_combo['values'] = ports
        if ports:
            self.port_combo.current(0)
        self.log("Available ports: " + ", ".join(ports) if ports else "No ports found")
            
    def toggle_connection(self):
        """Connect or disconnect from serial port"""
        if self.serial_port and self.serial_port.is_open:
            self.disconnect()
        else:
            self.connect()
            
    def connect(self):
        """Connect to selected serial port"""
        port = self.port_combo.get()
        if not port:
            messagebox.showerror("Error", "Please select a COM port")
            return
            
        try:
            self.serial_port = serial.Serial(
                port=port,
                baudrate=9600,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1
            )
            
            self.running = True
            self.read_thread = threading.Thread(target=self.read_serial, daemon=True)
            self.read_thread.start()
            
            self.connection_status.set("Connected")
            self.connect_btn.configure(text="Disconnect")
            self.log(f"Connected to {port}")
            
            # Update status label color
            for widget in self.root.winfo_children():
                self.update_connection_label("green")
                
        except Exception as e:
            messagebox.showerror("Connection Error", str(e))
            self.log(f"Error: {e}")
            
    def disconnect(self):
        """Disconnect from serial port"""
        self.running = False
        if self.serial_port:
            self.serial_port.close()
            self.serial_port = None
            
        self.connection_status.set("Disconnected")
        self.connect_btn.configure(text="Connect")
        self.update_connection_label("red")
        self.log("Disconnected")
        
    def update_connection_label(self, color):
        """Update connection status label color"""
        # Find and update the label
        pass  # Color is set via foreground in label creation
        
    def read_serial(self):
        """Read data from serial port in background thread"""
        # Command response tracking
        pending_command = None
        
        while self.running:
            try:
                if self.serial_port and self.serial_port.is_open:
                    # Poll for data periodically
                    if self.serial_port.in_waiting > 0:
                        data = self.serial_port.read(1)  # Read one byte
                        if data:
                            byte_val = data[0]
                            self.root.after(0, self.process_response, byte_val)
                                
            except Exception as e:
                self.root.after(0, self.log, f"Read error: {e}")
                
            time.sleep(0.05)
            
    def process_response(self, byte_val):
        """Process single byte response from PIC based on pending command"""
        self.log(f"RX: 0x{byte_val:02X} ({byte_val})")
        
        # Store response based on last command sent
        if hasattr(self, 'last_command'):
            cmd = self.last_command
            if cmd == 0x01:  # Desired temp fraction
                self.desired_frac = byte_val
                self.update_desired_display()
            elif cmd == 0x02:  # Desired temp integer
                self.desired_int = byte_val
                self.update_desired_display()
            elif cmd == 0x03:  # Ambient temp fraction
                self.ambient_frac = byte_val
                self.update_ambient_display()
            elif cmd == 0x04:  # Ambient temp integer
                self.ambient_int = byte_val
                self.update_ambient_display()
            elif cmd == 0x05:  # Fan speed
                self.fan_speed.set(str(byte_val))
            self.last_command = None
                
    def update_desired_display(self):
        """Update desired temperature display"""
        if hasattr(self, 'desired_int') and hasattr(self, 'desired_frac'):
            self.desired_temp.set(f"{self.desired_int}.{self.desired_frac:02d}")
            
    def update_ambient_display(self):
        """Update ambient temperature display"""
        if hasattr(self, 'ambient_int') and hasattr(self, 'ambient_frac'):
            self.ambient_temp.set(f"{self.ambient_int}.{self.ambient_frac:02d}")
            
    def process_data(self, data):
        """Process received text data from PIC (legacy)"""
        self.log(f"RX: {data}")
            
    def set_temperature(self):
        """Send new desired temperature to PIC via binary protocol"""
        try:
            temp_str = self.new_temp_entry.get().strip()
            
            # Validate format
            if '.' in temp_str:
                int_part, frac_part = temp_str.split('.')
                int_val = int(int_part)
                # Pad or truncate fraction to 2 digits
                frac_part = (frac_part + "00")[:2]
                frac_val = int(frac_part)
            else:
                int_val = int(temp_str)
                frac_val = 0
                
            # Range check
            if int_val < 10 or int_val > 50:
                messagebox.showerror("Error", "Temperature must be between 10.0 and 50.0")
                return
            if int_val == 50 and frac_val > 0:
                messagebox.showerror("Error", "Maximum temperature is 50.0")
                return
                
            # Send integer part: 11xxxxxx (0xC0 | value)
            int_cmd = 0xC0 | (int_val & 0x3F)
            self.send_byte(int_cmd)
            self.log(f"TX: Set INT = {int_val} (0x{int_cmd:02X})")
            
            time.sleep(0.05)  # Small delay between commands
            
            # Send fractional part: 10xxxxxx (0x80 | value)
            frac_cmd = 0x80 | (frac_val & 0x3F)
            self.send_byte(frac_cmd)
            self.log(f"TX: Set FRAC = {frac_val} (0x{frac_cmd:02X})")
            
            # Update display
            self.desired_temp.set(f"{int_val}.{frac_val:02d}")
            
        except ValueError:
            messagebox.showerror("Error", "Invalid temperature format. Use XX.X or XX.XX")
            
    def quick_set(self, temp):
        """Quick set temperature from preset button"""
        self.new_temp_entry.delete(0, tk.END)
        self.new_temp_entry.insert(0, f"{temp}.0")
        self.set_temperature()
        
    def send_command(self, command):
        """Send text command to PIC via UART (legacy)"""
        if self.serial_port and self.serial_port.is_open:
            try:
                self.serial_port.write(command.encode('utf-8'))
                self.log(f"TX: {command}")
            except Exception as e:
                self.log(f"Send error: {e}")
        else:
            messagebox.showwarning("Warning", "Not connected to device")
            
    def send_byte(self, byte_val):
        """Send single byte to PIC via UART"""
        if self.serial_port and self.serial_port.is_open:
            try:
                self.serial_port.write(bytes([byte_val]))
            except Exception as e:
                self.log(f"Send error: {e}")
        else:
            messagebox.showwarning("Warning", "Not connected to device")
            
    def request_data(self, cmd):
        """Send a GET command and track it for response"""
        self.last_command = cmd
        self.send_byte(cmd)
        
    def poll_device(self):
        """Periodically poll device for updates"""
        if self.serial_port and self.serial_port.is_open:
            # Request all data in sequence
            self.request_data(0x02)  # Desired INT
            time.sleep(0.1)
            self.request_data(0x01)  # Desired FRAC
            time.sleep(0.1)
            self.request_data(0x04)  # Ambient INT
            time.sleep(0.1)
            self.request_data(0x03)  # Ambient FRAC
            time.sleep(0.1)
            self.request_data(0x05)  # Fan speed
            
    def poll_device_async(self):
        """Start polling in background thread"""
        if self.serial_port and self.serial_port.is_open:
            threading.Thread(target=self.poll_device, daemon=True).start()
        else:
            messagebox.showwarning("Warning", "Not connected to device")
            
    def log(self, message):
        """Add message to log"""
        timestamp = time.strftime("%H:%M:%S")
        self.log_text.insert(tk.END, f"[{timestamp}] {message}\n")
        self.log_text.see(tk.END)
        
        # Limit log size
        lines = int(self.log_text.index('end-1c').split('.')[0])
        if lines > 100:
            self.log_text.delete('1.0', '2.0')
            
    def on_closing(self):
        """Handle window close"""
        self.running = False
        if self.serial_port:
            self.serial_port.close()
        self.root.destroy()


def main():
    root = tk.Tk()
    app = TemperatureControlUI(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()


if __name__ == "__main__":
    main()