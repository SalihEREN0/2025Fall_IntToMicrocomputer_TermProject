"""
PIC16F877A Smart Home Control System
Main GUI Application
"""

import tkinter as tk
from tkinter import ttk, messagebox
import serial.tools.list_ports
import time

from protocol import SerialManager, UART_CONFIG, DEFAULT_PORT_UI
from air_conditioner import AirConditionerPanel
from curtain_control import CurtainControlPanel


class MainApplication(tk.Tk):
    """Main application window"""
    
    def __init__(self):
        super().__init__()
        
        self.title("PIC16F877A Smart Home Control")
        self.geometry("700x650")
        self.resizable(False, False)
        
        # Serial connection
        self.serial_manager = SerialManager()
        self.connection_status = tk.StringVar(value="Disconnected")
        
        self._create_menu()
        self._create_widgets()
        self._refresh_ports()
        
        # Handle window close
        self.protocol("WM_DELETE_WINDOW", self._on_closing)
    
    def _create_menu(self):
        """Create menu bar"""
        menubar = tk.Menu(self)
        self.config(menu=menubar)
        
        # File menu
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="File", menu=file_menu)
        file_menu.add_command(label="Refresh Ports", command=self._refresh_ports)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self._on_closing)
        
        # Help menu
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Help", menu=help_menu)
        help_menu.add_command(label="About", command=self._show_about)
    
    def _create_widgets(self):
        """Create main widgets"""
        
        # Connection Frame
        conn_frame = ttk.LabelFrame(self, text="Connection", padding="10")
        conn_frame.pack(fill="x", padx=10, pady=5)
        
        ttk.Label(conn_frame, text="Port:").grid(row=0, column=0, padx=5)
        self.port_combo = ttk.Combobox(conn_frame, width=15, state="readonly")
        self.port_combo.grid(row=0, column=1, padx=5)
        
        ttk.Button(conn_frame, text="🔄", width=3, 
                  command=self._refresh_ports).grid(row=0, column=2, padx=2)
        
        self.connect_btn = ttk.Button(conn_frame, text="Connect", width=12,
                                      command=self._toggle_connection)
        self.connect_btn.grid(row=0, column=3, padx=10)
        
        # Status indicator
        self.status_label = ttk.Label(conn_frame, textvariable=self.connection_status,
                                      font=("Arial", 10, "bold"), foreground="red")
        self.status_label.grid(row=0, column=4, padx=20)
        
        # UART info
        baud_info = f"UART: {UART_CONFIG['baudrate']} baud, 8N1"
        ttk.Label(conn_frame, text=baud_info, foreground="gray").grid(
            row=0, column=5, padx=10)
        
        # Notebook for tabs
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=10, pady=5)
        
        # Air Conditioner Tab
        self.ac_panel = AirConditionerPanel(self.notebook, self.serial_manager)
        self.ac_panel.log = self._log  # Override log method
        self.notebook.add(self.ac_panel, text="🌡️ Air Conditioner")
        
        # Curtain Control Tab
        self.curtain_panel = CurtainControlPanel(self.notebook, self.serial_manager)
        self.curtain_panel.log = self._log
        self.notebook.add(self.curtain_panel, text="🪟 Curtain Control")
        
        # Log Frame
        log_frame = ttk.LabelFrame(self, text="Communication Log", padding="5")
        log_frame.pack(fill="x", padx=10, pady=5)
        
        self.log_text = tk.Text(log_frame, height=8, width=80, 
                                font=("Consolas", 9))
        self.log_text.pack(side="left", fill="both", expand=True)
        
        scrollbar = ttk.Scrollbar(log_frame, orient="vertical", 
                                  command=self.log_text.yview)
        scrollbar.pack(side="right", fill="y")
        self.log_text.configure(yscrollcommand=scrollbar.set)
    
    def _refresh_ports(self):
        """Refresh available COM ports"""
        ports = SerialManager.list_ports()
        self.port_combo['values'] = ports
        
        # Try to select default port
        if DEFAULT_PORT_UI in ports:
            self.port_combo.set(DEFAULT_PORT_UI)
        elif ports:
            self.port_combo.current(0)
        
        self._log(f"Available ports: {', '.join(ports) if ports else 'None'}")
    
    def _toggle_connection(self):
        """Toggle serial connection"""
        if self.serial_manager.is_connected:
            self._disconnect()
        else:
            self._connect()
    
    def _connect(self):
        """Connect to serial port"""
        port = self.port_combo.get()
        if not port:
            messagebox.showerror("Error", "Please select a COM port")
            return
        
        if self.serial_manager.connect(port):
            self.connection_status.set("Connected")
            self.status_label.configure(foreground="green")
            self.connect_btn.configure(text="Disconnect")
            
            # Update panels
            self.ac_panel.set_serial_manager(self.serial_manager)
            self.curtain_panel.set_serial_manager(self.serial_manager)
            
            self._log(f"Connected to {port}")
        else:
            messagebox.showerror("Error", f"Failed to connect to {port}")
    
    def _disconnect(self):
        """Disconnect from serial port"""
        # Stop polling in panels
        self.ac_panel.stop()
        self.curtain_panel.stop()
        
        self.serial_manager.disconnect()
        self.connection_status.set("Disconnected")
        self.status_label.configure(foreground="red")
        self.connect_btn.configure(text="Connect")
        self._log("Disconnected")
    
    def _log(self, message: str):
        """Add message to log"""
        timestamp = time.strftime("%H:%M:%S")
        self.log_text.insert("end", f"[{timestamp}] {message}\n")
        self.log_text.see("end")
        
        # Limit log size
        lines = int(self.log_text.index('end-1c').split('.')[0])
        if lines > 200:
            self.log_text.delete('1.0', '50.0')
    
    def _show_about(self):
        """Show about dialog"""
        messagebox.showinfo(
            "About",
            "PIC16F877A Smart Home Control\n\n"
            "Modules:\n"
            "• Air Conditioner Control\n"
            "• Curtain Control (Coming Soon)\n\n"
            "UART Protocol: 9600 baud, 8N1\n"
            "COM Ports: COM14 ↔ COM15 (com0com)\n\n"
            "Version 1.0"
        )
    
    def _on_closing(self):
        """Handle window close"""
        self.ac_panel.stop()
        self.curtain_panel.stop()
        
        if self.serial_manager.is_connected:
            self.serial_manager.disconnect()
        
        self.destroy()


def main():
    """Main entry point"""
    app = MainApplication()
    app.mainloop()


if __name__ == "__main__":
    main()
