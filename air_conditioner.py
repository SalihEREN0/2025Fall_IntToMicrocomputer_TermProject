"""
Air Conditioner Control Module
UI component for PIC16F877A Temperature Control System
"""

import tkinter as tk
from tkinter import ttk, messagebox
import threading
import time

from protocol import (
    Command, Temperature, SystemStatus, SerialManager,
    encode_set_desired_int, encode_set_desired_frac,
    DEFAULT_PORT_UI
)


class AirConditionerPanel(ttk.Frame):
    """Air Conditioner control panel widget"""
    
    def __init__(self, parent, serial_manager: SerialManager = None):
        super().__init__(parent, padding="10")
        
        self.serial_manager = serial_manager or SerialManager()
        self.status = SystemStatus()
        
        # Data variables
        self.desired_temp = tk.StringVar(value="27.00")
        self.ambient_temp = tk.StringVar(value="--.-")
        self.fan_speed = tk.StringVar(value="---")
        self.heater_status = tk.StringVar(value="OFF")
        self.cooler_status = tk.StringVar(value="OFF")
        
        # Polling control
        self.polling = False
        self.poll_thread = None
        
        self._create_widgets()
    
    def _create_widgets(self):
        """Create UI widgets"""
        
        # Title
        title = ttk.Label(self, text="🌡️ Air Conditioner Control", 
                         font=("Arial", 14, "bold"))
        title.grid(row=0, column=0, columnspan=3, pady=(0, 15))
        
        # Temperature Display Frame
        temp_frame = ttk.LabelFrame(self, text="Temperatures", padding="15")
        temp_frame.grid(row=1, column=0, columnspan=3, sticky="ew", pady=5)
        
        # Desired Temperature
        ttk.Label(temp_frame, text="Desired:", font=("Arial", 11)).grid(
            row=0, column=0, sticky="w", pady=5)
        ttk.Label(temp_frame, textvariable=self.desired_temp, 
                 font=("Arial", 20, "bold"), foreground="blue").grid(
            row=0, column=1, padx=15)
        ttk.Label(temp_frame, text="°C", font=("Arial", 14)).grid(
            row=0, column=2)
        
        # Ambient Temperature
        ttk.Label(temp_frame, text="Ambient:", font=("Arial", 11)).grid(
            row=1, column=0, sticky="w", pady=5)
        ttk.Label(temp_frame, textvariable=self.ambient_temp,
                 font=("Arial", 20, "bold"), foreground="green").grid(
            row=1, column=1, padx=15)
        ttk.Label(temp_frame, text="°C", font=("Arial", 14)).grid(
            row=1, column=2)
        
        # Fan Speed
        ttk.Label(temp_frame, text="Fan Speed:", font=("Arial", 11)).grid(
            row=2, column=0, sticky="w", pady=5)
        ttk.Label(temp_frame, textvariable=self.fan_speed,
                 font=("Arial", 20, "bold"), foreground="orange").grid(
            row=2, column=1, padx=15)
        ttk.Label(temp_frame, text="RPS", font=("Arial", 14)).grid(
            row=2, column=2)
        
        # Status Frame
        status_frame = ttk.LabelFrame(self, text="Device Status", padding="10")
        status_frame.grid(row=2, column=0, columnspan=3, sticky="ew", pady=10)
        
        # Heater
        ttk.Label(status_frame, text="Heater:", font=("Arial", 11)).grid(
            row=0, column=0, padx=10)
        self.heater_label = ttk.Label(status_frame, textvariable=self.heater_status,
                                      font=("Arial", 12, "bold"))
        self.heater_label.grid(row=0, column=1, padx=5)
        self.heater_canvas = tk.Canvas(status_frame, width=25, height=25, 
                                       highlightthickness=0)
        self.heater_canvas.grid(row=0, column=2, padx=5)
        self.heater_indicator = self.heater_canvas.create_oval(2, 2, 22, 22, fill="gray")
        
        # Cooler
        ttk.Label(status_frame, text="Cooler:", font=("Arial", 11)).grid(
            row=0, column=3, padx=10)
        self.cooler_label = ttk.Label(status_frame, textvariable=self.cooler_status,
                                      font=("Arial", 12, "bold"))
        self.cooler_label.grid(row=0, column=4, padx=5)
        self.cooler_canvas = tk.Canvas(status_frame, width=25, height=25,
                                       highlightthickness=0)
        self.cooler_canvas.grid(row=0, column=5, padx=5)
        self.cooler_indicator = self.cooler_canvas.create_oval(2, 2, 22, 22, fill="gray")
        
        # Set Temperature Frame
        set_frame = ttk.LabelFrame(self, text="Set Desired Temperature", padding="10")
        set_frame.grid(row=3, column=0, columnspan=3, sticky="ew", pady=10)
        
        ttk.Label(set_frame, text="Temperature:", font=("Arial", 11)).grid(
            row=0, column=0, padx=5)
        self.temp_entry = ttk.Entry(set_frame, width=10, font=("Arial", 12))
        self.temp_entry.grid(row=0, column=1, padx=5)
        self.temp_entry.insert(0, "27.00")
        ttk.Label(set_frame, text="°C (10.0 - 50.0)").grid(row=0, column=2, padx=5)
        
        ttk.Button(set_frame, text="Set", command=self.set_temperature, 
                  width=10).grid(row=0, column=3, padx=10)
        
        # Preset buttons
        preset_frame = ttk.Frame(set_frame)
        preset_frame.grid(row=1, column=0, columnspan=4, pady=10)
        
        ttk.Label(preset_frame, text="Presets:").pack(side=tk.LEFT, padx=5)
        for temp in [18, 22, 25, 27, 30]:
            ttk.Button(preset_frame, text=f"{temp}°C", width=6,
                      command=lambda t=temp: self.quick_set(t)).pack(side=tk.LEFT, padx=2)
        
        # Control buttons
        ctrl_frame = ttk.Frame(self)
        ctrl_frame.grid(row=4, column=0, columnspan=3, pady=10)
        
        ttk.Button(ctrl_frame, text="🔄 Refresh", command=self.request_all_data,
                  width=12).pack(side=tk.LEFT, padx=5)
        self.poll_btn = ttk.Button(ctrl_frame, text="▶ Start Polling", 
                                   command=self.toggle_polling, width=14)
        self.poll_btn.pack(side=tk.LEFT, padx=5)
    
    def set_serial_manager(self, manager: SerialManager):
        """Set the serial manager (called from main GUI)"""
        self.serial_manager = manager
    
    def set_temperature(self):
        """Send new desired temperature to PIC"""
        try:
            temp_str = self.temp_entry.get().strip()
            temp = Temperature.from_float(float(temp_str))
            
            if not temp.is_valid():
                messagebox.showerror("Error", "Temperature must be between 10.0 and 50.0")
                return
            
            if not self.serial_manager.is_connected:
                messagebox.showwarning("Warning", "Not connected to device")
                return
            
            # Send integer part: 11xxxxxx
            int_cmd = 0xC0 | (temp.integer & 0x3F)
            self.serial_manager.send(bytes([int_cmd]))
            self.log(f"TX: Set INT = {temp.integer} (0x{int_cmd:02X})")
            
            time.sleep(0.05)
            
            # Send fractional part: 10xxxxxx
            frac_cmd = 0x80 | (temp.fraction & 0x3F)
            self.serial_manager.send(bytes([frac_cmd]))
            self.log(f"TX: Set FRAC = {temp.fraction} (0x{frac_cmd:02X})")
            
            # Update display
            self.desired_temp.set(str(temp))
            self.status.desired_temp = temp
            
        except ValueError:
            messagebox.showerror("Error", "Invalid temperature format")
    
    def quick_set(self, temp: int):
        """Set temperature from preset button"""
        self.temp_entry.delete(0, tk.END)
        self.temp_entry.insert(0, f"{temp}.00")
        self.set_temperature()
    
    def request_all_data(self):
        """Request all data from PIC"""
        if not self.serial_manager.is_connected:
            messagebox.showwarning("Warning", "Not connected to device")
            return
        
        threading.Thread(target=self._poll_once, daemon=True).start()
    
    def _poll_once(self):
        """Poll all values once"""
        try:
            # Request Desired INT
            self.serial_manager.send(bytes([Command.GET_DESIRED_INT]))
            time.sleep(0.1)
            data = self.serial_manager.receive(1)
            if data:
                self.status.desired_temp.integer = data[0]
                self.log(f"RX: Desired INT = {data[0]}")
            
            # Request Desired FRAC
            self.serial_manager.send(bytes([Command.GET_DESIRED_FRAC]))
            time.sleep(0.1)
            data = self.serial_manager.receive(1)
            if data:
                self.status.desired_temp.fraction = data[0]
                self.log(f"RX: Desired FRAC = {data[0]}")
            
            # Request Ambient INT
            self.serial_manager.send(bytes([Command.GET_AMBIENT_INT]))
            time.sleep(0.1)
            data = self.serial_manager.receive(1)
            if data:
                self.status.ambient_temp.integer = data[0]
                self.log(f"RX: Ambient INT = {data[0]}")
            
            # Request Ambient FRAC
            self.serial_manager.send(bytes([Command.GET_AMBIENT_FRAC]))
            time.sleep(0.1)
            data = self.serial_manager.receive(1)
            if data:
                self.status.ambient_temp.fraction = data[0]
                self.log(f"RX: Ambient FRAC = {data[0]}")
            
            # Request Fan Speed
            self.serial_manager.send(bytes([Command.GET_FAN_SPEED]))
            time.sleep(0.1)
            data = self.serial_manager.receive(1)
            if data:
                self.status.fan_speed = data[0]
                self.log(f"RX: Fan Speed = {data[0]} RPS")
            
            # Update UI
            self.after(0, self._update_display)
            
        except Exception as e:
            self.log(f"Poll error: {e}")
    
    def _update_display(self):
        """Update UI with current status"""
        self.desired_temp.set(str(self.status.desired_temp))
        self.ambient_temp.set(str(self.status.ambient_temp))
        self.fan_speed.set(str(self.status.fan_speed))
        
        # Determine heater/cooler status based on temps
        desired = self.status.desired_temp.to_float()
        ambient = self.status.ambient_temp.to_float()
        
        if desired > ambient:
            self.heater_status.set("ON")
            self.cooler_status.set("OFF")
            self.heater_canvas.itemconfig(self.heater_indicator, fill="red")
            self.cooler_canvas.itemconfig(self.cooler_indicator, fill="gray")
        elif desired < ambient:
            self.heater_status.set("OFF")
            self.cooler_status.set("ON")
            self.heater_canvas.itemconfig(self.heater_indicator, fill="gray")
            self.cooler_canvas.itemconfig(self.cooler_indicator, fill="cyan")
        else:
            self.heater_status.set("OFF")
            self.cooler_status.set("OFF")
            self.heater_canvas.itemconfig(self.heater_indicator, fill="gray")
            self.cooler_canvas.itemconfig(self.cooler_indicator, fill="gray")
    
    def toggle_polling(self):
        """Toggle automatic polling"""
        if self.polling:
            self.polling = False
            self.poll_btn.configure(text="▶ Start Polling")
        else:
            if not self.serial_manager.is_connected:
                messagebox.showwarning("Warning", "Not connected to device")
                return
            self.polling = True
            self.poll_btn.configure(text="⏹ Stop Polling")
            self.poll_thread = threading.Thread(target=self._polling_loop, daemon=True)
            self.poll_thread.start()
    
    def _polling_loop(self):
        """Continuous polling loop"""
        while self.polling and self.serial_manager.is_connected:
            self._poll_once()
            time.sleep(2)  # Poll every 2 seconds
    
    def log(self, message: str):
        """Log message (override in main GUI to show in log panel)"""
        print(f"[AC] {message}")
    
    def stop(self):
        """Stop polling when closing"""
        self.polling = False
