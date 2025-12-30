"""
Curtain Control Module
UI component for motorized curtain control system
(To be implemented)
"""

import tkinter as tk
from tkinter import ttk

from protocol import SerialManager


class CurtainControlPanel(ttk.Frame):
    """Curtain control panel widget (placeholder)"""
    
    def __init__(self, parent, serial_manager: SerialManager = None):
        super().__init__(parent, padding="10")
        
        self.serial_manager = serial_manager
        
        self._create_widgets()
    
    def _create_widgets(self):
        """Create placeholder UI"""
        
        # Title
        title = ttk.Label(self, text="🪟 Curtain Control", 
                         font=("Arial", 14, "bold"))
        title.grid(row=0, column=0, pady=(0, 15))
        
        # Placeholder message
        placeholder = ttk.Label(
            self, 
            text="Curtain control module\ncoming soon...",
            font=("Arial", 12),
            foreground="gray",
            justify="center"
        )
        placeholder.grid(row=1, column=0, pady=50)
        
        # Placeholder controls (disabled)
        ctrl_frame = ttk.LabelFrame(self, text="Controls (Disabled)", padding="10")
        ctrl_frame.grid(row=2, column=0, sticky="ew", pady=10)
        
        ttk.Button(ctrl_frame, text="⬆ Open", state="disabled", width=15).grid(
            row=0, column=0, padx=5, pady=5)
        ttk.Button(ctrl_frame, text="⏹ Stop", state="disabled", width=15).grid(
            row=0, column=1, padx=5, pady=5)
        ttk.Button(ctrl_frame, text="⬇ Close", state="disabled", width=15).grid(
            row=0, column=2, padx=5, pady=5)
        
        # Position slider (disabled)
        ttk.Label(ctrl_frame, text="Position:").grid(row=1, column=0, pady=10)
        slider = ttk.Scale(ctrl_frame, from_=0, to=100, orient="horizontal", 
                          length=200)
        slider.grid(row=1, column=1, columnspan=2, pady=10)
        slider.state(['disabled'])
    
    def set_serial_manager(self, manager: SerialManager):
        """Set the serial manager"""
        self.serial_manager = manager
    
    def log(self, message: str):
        """Log message"""
        print(f"[Curtain] {message}")
    
    def stop(self):
        """Cleanup when closing"""
        pass
