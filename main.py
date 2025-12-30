import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import serial
import serial.tools.list_ports
import time
from abc import ABC, abstractmethod

# ==============================================================================
# 1. API KATMANI (SENKRONİZASYON SORUNU DÜZELTİLDİ)
# ==============================================================================

class HomeAutomationSystemConnection(ABC):
    def __init__(self):
        self.comPort = 0
        self.baudRate = 9600
        self.ser = None

    def setComPort(self, port: int):
        self.comPort = port

    def setBaudRate(self, rate: int):
        self.baudRate = rate

    def open(self) -> bool:
        try:
            port_name = f"COM{self.comPort}"
            # Timeout arttırıldı (R2.3-2)
            self.ser = serial.Serial(port_name, self.baudRate, timeout=0.5)
            # board2ui.py'deki kararlı ayarlar
            self.ser.dtr = False
            self.ser.rts = False
            self.ser.flushInput()  # Açılışta buffer'ı temizle
            self.ser.flushOutput()
            return True
        except Exception as e:
            print(f"Bağlantı Hatası ({port_name}): {e}")
            return False

    def close(self) -> bool:
        if self.ser and self.ser.is_open:
            self.ser.close()
            return True
        return False

    def is_connected(self) -> bool:
        return self.ser is not None and self.ser.is_open

    def _send_command(self, cmd_byte) -> int:
        """
        DÜZELTME: Gönder ve Cevap Bekle (Smart Read)
        Eski kod sadece uyuyup okuyordu, bu ise veri gelene kadar bekler.
        """
        if not self.is_connected(): return 0
        
        try:
            # Buffer'da kalan eski (gecikmiş) verileri temizle ki senkron kaymasın
            self.ser.reset_input_buffer() 
            
            # Komutu gönder
            self.ser.write(bytes([cmd_byte]))
            
            # Cevabı bekle (Max 1.0 saniye)
            # BMP180 gibi sensörler I2C üzerinden okunduğu için PIC hemen cevap veremeyebilir.
            start_time = time.time()
            while (time.time() - start_time) < 1.0:
                if self.ser.in_waiting > 0:
                    data = self.ser.read(1)
                    return int.from_bytes(data, byteorder='big')
                time.sleep(0.01) # CPU'yu yormamak için minik bekleme
            
            print(f"Timeout: Komut {hex(cmd_byte)} için cevap gelmedi.")
            return 0 # Timeout
        except Exception as e:
            print(f"IO Error: {e}")
            return 0

    @abstractmethod
    def update(self): pass


class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def update(self):
        if not self.is_connected(): return
        
        # 1. Desired Temp
        d_frac = self._send_command(0x01)
        d_int = self._send_command(0x02)
        self.desiredTemperature = float(f"{d_int}.{d_frac}")

        # 2. Ambient Temp
        a_frac = self._send_command(0x03)
        a_int = self._send_command(0x04)
        self.ambientTemperature = float(f"{a_int}.{a_frac}")

        # 3. Fan Speed
        self.fanSpeed = self._send_command(0x05)

    def setDesiredTemp(self, temp: float) -> bool:
        if not self.is_connected(): return False
        try:
            val_int = int(temp)
            val_frac = int((temp - val_int) * 10)
            if val_frac > 63: val_frac = 63

            cmd_frac = 0x80 | (val_frac & 0x3F)
            cmd_int = 0xC0 | (val_int & 0x3F)

            self.ser.write(bytes([cmd_frac]))
            time.sleep(0.05)
            self.ser.write(bytes([cmd_int]))
            return True
        except: return False

    def getAmbientTemp(self): return self.ambientTemperature
    def getDesiredTemp(self): return self.desiredTemperature
    def getFanSpeed(self): return self.fanSpeed


class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    # board2.asm'deki komutlar
    CMD_GET_CURTAIN = 0x02  # Perdeyi Sor
    CMD_GET_LIGHT = 0x08    # Işığı Sor
    
    def __init__(self):
        super().__init__()
        self.curtainStatus = 0.0
        self.outdoorTemperature = 25.0  # Sabit değer (board2.asm'de komut yok)
        self.outdoorPressure = 1013.0   # Sabit değer (board2.asm'de komut yok)
        self.lightIntensity = 0.0

    def _read_single_byte(self, cmd_byte) -> int:
        """
        board2ui.py tarzı: Tek byte gönder, tek byte al.
        """
        if not self.is_connected(): return 0
        
        try:
            self.ser.reset_input_buffer()
            self.ser.write(bytes([cmd_byte]))
            time.sleep(0.15)  # PIC'in cevaplaması için süre
            
            # Veri gelene kadar bekle (max 0.5 saniye)
            start_time = time.time()
            while (time.time() - start_time) < 0.5:
                if self.ser.in_waiting > 0:
                    raw_byte = self.ser.read(1)
                    int_val = int.from_bytes(raw_byte, byteorder='big')
                    print(f"<< Komut {hex(cmd_byte)} -> Raw: {raw_byte} -> Sayı: {int_val}")
                    return int_val
                time.sleep(0.01)
            
            print(f"Timeout: Komut {hex(cmd_byte)} için cevap gelmedi.")
            return 0
        except Exception as e:
            print(f"IO Error: {e}")
            return 0

    def update(self):
        """
        board2.asm'ye uygun okuma.
        Sadece 0x02 (curtain) ve 0x08 (light) komutları mevcut.
        Temp ve Pressure sabit değer olarak gösterilir.
        """
        if not self.is_connected(): return

        # 1. Perde Durumu (Curtain) - Komut: 0x02
        curtain_val = self._read_single_byte(self.CMD_GET_CURTAIN)
        self.curtainStatus = float(curtain_val)
        
        time.sleep(0.1)

        # 2. Işık (Light) - Komut: 0x08
        light_val = self._read_single_byte(self.CMD_GET_LIGHT)
        self.lightIntensity = float(light_val)
        
        # Temp ve Pressure board2.asm'de desteklenmiyor, sabit kalır
        # self.outdoorTemperature = 25.0
        # self.outdoorPressure = 1013.0
        
        # DEBUG: Konsoldan değerleri kontrol et
        print(f"[DEBUG] Curtain: {self.curtainStatus}% | Light: {self.lightIntensity} Lux")

    def setCurtainStatus(self, std: float) -> bool:
        """
        board2ui.py tarzı: Sadece 0xC0 | val şeklinde tek byte gönder.
        """
        if not self.is_connected(): return False
        try:
            val = int(std)
            
            cmd = 0xC0 | (val & 0x3F)
            self.ser.write(bytes([cmd]))
            print(f">> Gönderildi: {cmd} (Hex: {hex(cmd)})")
            return True
        except Exception as e:
            print(f"setCurtainStatus Error: {e}")
            return False

    def getCurtainStatus(self): return self.curtainStatus
    def getOutdoorTemp(self): return self.outdoorTemperature
    def getOutdoorPress(self): return self.outdoorPressure
    def getLightIntensity(self): return self.lightIntensity


# ==============================================================================
# 2. ARAYÜZ KATMANI (GUI)
# ==============================================================================

class HomeAutomationApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("ESOGU Home Automation System (Robust)")
        self.geometry("600x550")
        self.resizable(False, False)
        
        self.ac_api = AirConditionerSystemConnection()
        self.curtain_api = CurtainControlSystemConnection()
        
        self.container = tk.Frame(self)
        self.container.pack(fill="both", expand=True, padx=20, pady=20)
        
        self.show_main_menu()
        
        # Güncelleme Hızı: Sensörlerin yetişmesi için 2 saniye idealdir (Doküman önerisi)
        self.update_interval = 2000 
        self.update_data_loop()

    def clear_screen(self):
        for widget in self.container.winfo_children():
            widget.destroy()

    def ask_port_connection(self, api_obj, system_name):
        popup = tk.Toplevel(self)
        popup.title(f"Connect {system_name}")
        popup.geometry("300x150")
        
        tk.Label(popup, text=f"Port for {system_name}:").pack(pady=5)
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
        self.clear_screen()
        frame = tk.LabelFrame(self.container, text="MAIN MENU", font=("Arial", 14, "bold"), padx=20, pady=20)
        frame.pack(expand=True)
        tk.Button(frame, text="1. Air Conditioner", width=25, command=self.on_ac).pack(pady=5)
        tk.Button(frame, text="2. Curtain Control", width=25, command=self.on_cc).pack(pady=5)
        tk.Button(frame, text="3. Exit", width=25, bg="red", fg="white", command=self.quit_app).pack(pady=5)

    def on_ac(self):
        if not self.ac_api.is_connected(): self.ask_port_connection(self.ac_api, "Air Conditioner")
        if self.ac_api.is_connected(): self.show_ac()

    def on_cc(self):
        if not self.curtain_api.is_connected(): self.ask_port_connection(self.curtain_api, "Curtain")
        if self.curtain_api.is_connected(): self.show_cc()

    def show_ac(self):
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
        val = simpledialog.askfloat("Input", "Temp (10-50):", minvalue=10, maxvalue=50)
        if val: self.ac_api.setDesiredTemp(val)

    def show_cc(self):
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
        val = simpledialog.askfloat("Input", "Curtain %:")
        if val is not None: self.curtain_api.setCurtainStatus(val)

    def update_data_loop(self):
        if self.ac_api.is_connected(): self.ac_api.update()
        if self.curtain_api.is_connected(): self.curtain_api.update()

        try:
            if hasattr(self, 'lbl_ac1') and self.lbl_ac1.winfo_exists():
                self.lbl_ac1.config(text=f"Home Ambient Temperature: {self.ac_api.getAmbientTemp():.1f} C")
                self.lbl_ac2.config(text=f"Home Desired Temperature: {self.ac_api.getDesiredTemp():.1f} C")
                self.lbl_ac3.config(text=f"Fan Speed: {self.ac_api.getFanSpeed()} rps")

            if hasattr(self, 'lbl_cc1') and self.lbl_cc1.winfo_exists():
                self.lbl_cc1.config(text=f"Outdoor Temperature: {self.curtain_api.getOutdoorTemp():.1f} C")
                self.lbl_cc2.config(text=f"Outdoor Pressure: {self.curtain_api.getOutdoorPress():.0f} hPa")
                self.lbl_cc3.config(text=f"Curtain Status: {self.curtain_api.getCurtainStatus():.0f} %")
                self.lbl_cc4.config(text=f"Light Intensity: {self.curtain_api.getLightIntensity():.0f} Lux")
        except: pass
        self.after(self.update_interval, self.update_data_loop)

    def quit_app(self):
        self.ac_api.close()
        self.curtain_api.close()
        self.destroy()

if __name__ == "__main__":
    app = HomeAutomationApp()
    app.mainloop()