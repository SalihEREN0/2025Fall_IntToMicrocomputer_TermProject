import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import serial
import serial.tools.list_ports
import time
from abc import ABC, abstractmethod

# ==============================================================================
# 1. API KATMANI (BACKEND)
# Doküman Figure 17 UML Diyagramı ve Byte Protokollerine Uygun
# ==============================================================================

class HomeAutomationSystemConnection(ABC):
    """
    Doküman UML Referansı: Figure 17
    Temel bağlantı ve port yönetim sınıfı.
    """
    def __init__(self):
        self.comPort = 0
        self.baudRate = 9600
        self.ser = None # Serial nesnesi

    def setComPort(self, port: int):
        self.comPort = port

    def setBaudRate(self, rate: int):
        self.baudRate = rate

    def open(self) -> bool:
        """Portu açmayı dener."""
        try:
            port_name = f"COM{self.comPort}"
            # Timeout, veri okurken programın donmasını engeller
            self.ser = serial.Serial(port_name, self.baudRate, timeout=0.2)
            return True
        except Exception as e:
            print(f"Bağlantı Hatası ({port_name}): {e}")
            return False

    def close(self) -> bool:
        """Portu kapatır."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            return True
        return False

    def is_connected(self) -> bool:
        return self.ser is not None and self.ser.is_open

    def _send_byte(self, byte_val):
        """Yardımcı fonksiyon: Tek byte gönderir."""
        if self.is_connected():
            try:
                self.ser.write(bytes([byte_val]))
                time.sleep(0.05) # PIC'in işlemesi için minik gecikme
            except:
                pass

    def _read_byte(self) -> int:
        """Yardımcı fonksiyon: Tek byte okur."""
        if self.is_connected():
            try:
                data = self.ser.read(1)
                if data:
                    return int.from_bytes(data, byteorder='big')
            except:
                pass
        return 0

    @abstractmethod
    def update(self):
        pass


class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    """
    Doküman Kaynak 197 (Source 197) Protokolü
    Board #1: Klima Sistemi
    """
    def __init__(self):
        super().__init__()
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def update(self):
        if not self.is_connected(): return

        try:
            # 1. İstenen Sıcaklık (Low:0x01, High:0x02)
            self._send_byte(0x01)
            d_frac = self._read_byte()
            self._send_byte(0x02)
            d_int = self._read_byte()
            self.desiredTemperature = float(f"{d_int}.{d_frac}")

            # 2. Ortam Sıcaklığı (Low:0x03, High:0x04)
            self._send_byte(0x03)
            a_frac = self._read_byte()
            self._send_byte(0x04)
            a_int = self._read_byte()
            self.ambientTemperature = float(f"{a_int}.{a_frac}")

            # 3. Fan Hızı (0x05)
            self._send_byte(0x05)
            self.fanSpeed = self._read_byte()
        except Exception as e:
            print(f"AC Update Error: {e}")

    def setDesiredTemp(self, temp: float) -> bool:
        if not self.is_connected(): return False
        try:
            val_int = int(temp)
            val_frac = int((temp - val_int) * 100) # Virgülden sonrasını al
            if val_frac > 63: val_frac = 63 # 6-bit sınırı

            # Protokol: 10xxxxxx (Frac), 11xxxxxx (Int)
            cmd_frac = 0x80 | (val_frac & 0x3F)
            cmd_int = 0xC0 | (val_int & 0x3F)

            self._send_byte(cmd_frac)
            self._send_byte(cmd_int)
            return True
        except:
            return False

    # Getters
    def getAmbientTemp(self): return self.ambientTemperature
    def getDesiredTemp(self): return self.desiredTemperature
    def getFanSpeed(self): return self.fanSpeed


class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    """
    Doküman Kaynak 233 (Source 233) Protokolü
    Board #2: Perde Sistemi
    """
    def __init__(self):
        super().__init__()
        self.curtainStatus = 0.0
        self.outdoorTemperature = 0.0
        self.outdoorPressure = 0.0
        self.lightIntensity = 0.0

    def update(self):
        if not self.is_connected(): return

        try:
            # 1. Perde Durumu (0x01, 0x02)
            self._send_byte(0x01)
            c_frac = self._read_byte()
            self._send_byte(0x02)
            c_int = self._read_byte()
            self.curtainStatus = float(f"{c_int}.{c_frac}")

            # 2. Dış Sıcaklık (0x03, 0x04)
            self._send_byte(0x03)
            t_frac = self._read_byte()
            self._send_byte(0x04)
            t_int = self._read_byte()
            self.outdoorTemperature = float(f"{t_int}.{t_frac}")

            # 3. Basınç (0x05, 0x06)
            self._send_byte(0x05)
            p_frac = self._read_byte()
            self._send_byte(0x06)
            p_int = self._read_byte()
            self.outdoorPressure = float(f"{p_int}.{p_frac}")

            # 4. Işık Şiddeti (0x07, 0x08)
            self._send_byte(0x07)
            l_frac = self._read_byte()
            self._send_byte(0x08)
            l_int = self._read_byte()
            self.lightIntensity = float(f"{l_int}.{l_frac}")
        except Exception as e:
            print(f"Curtain Update Error: {e}")

    def setCurtainStatus(self, std: float) -> bool:
        if not self.is_connected(): return False
        try:
            val_int = int(std)
            val_frac = int((std - val_int) * 100)
            if val_frac > 63: val_frac = 63

            # Protokol: 10xxxxxx (Frac), 11xxxxxx (Int)
            cmd_frac = 0x80 | (val_frac & 0x3F)
            cmd_int = 0xC0 | (val_int & 0x3F)

            self._send_byte(cmd_frac)
            self._send_byte(cmd_int)
            return True
        except:
            return False

    # Getters
    def getCurtainStatus(self): return self.curtainStatus
    def getOutdoorTemp(self): return self.outdoorTemperature
    def getOutdoorPress(self): return self.outdoorPressure
    def getLightIntensity(self): return self.lightIntensity


# ==============================================================================
# 2. ARAYÜZ KATMANI (GUI)
# Akış: Main Menu -> Port Seçimi (Pop-up) -> Kontrol Ekranı
# ==============================================================================

class HomeAutomationApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("ESOGU Home Automation System")
        self.geometry("600x500")
        self.resizable(False, False)
        
        # API Nesneleri (Başlangıçta kopuk)
        self.ac_api = AirConditionerSystemConnection()
        self.curtain_api = CurtainControlSystemConnection()
        
        # Ana Çerçeve
        self.container = tk.Frame(self)
        self.container.pack(fill="both", expand=True, padx=20, pady=20)
        
        # Başlangıç Ekranı: ANA MENÜ
        self.show_main_menu()
        
        # Arka Plan Veri Güncelleme Döngüsü
        self.update_interval = 1000 # 1 saniye
        self.update_data_loop()

    def clear_screen(self):
        """Ekranı temizler"""
        for widget in self.container.winfo_children():
            widget.destroy()

    # --- PORT SEÇİM PENCERESİ (POP-UP) ---
    def ask_port_connection(self, api_obj, system_name):
        """
        Kullanıcı bir sisteme girmek istediğinde port sormak için açılan pencere.
        """
        # Yeni bir küçük pencere aç
        popup = tk.Toplevel(self)
        popup.title(f"Connect to {system_name}")
        popup.geometry("350x180")
        popup.transient(self) # Ana pencerenin üstünde kalsın
        popup.grab_set()      # Diğer pencerelere tıklanmasın

        tk.Label(popup, text=f"Select COM Port for\n{system_name}", font=("Arial", 11, "bold")).pack(pady=10)

        # Bilgisayardaki aktif portları bul
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports: 
            ports = [f"COM{i}" for i in range(1, 10)] # Port yoksa varsayılan liste

        combo = ttk.Combobox(popup, values=ports, font=("Arial", 10))
        if ports: combo.current(0)
        else: combo.set("COM1")
        combo.pack(pady=5)

        def connect_action():
            selected_port_str = combo.get()
            try:
                # "COM3" -> 3 dönüşümü
                port_num = int(selected_port_str.upper().replace("COM", ""))
                
                api_obj.setComPort(port_num)
                if api_obj.open():
                    messagebox.showinfo("Success", f"Connected to {selected_port_str}!")
                    popup.destroy() # Pencereyi kapat, ana akışa dön
                else:
                    messagebox.showerror("Connection Failed", f"Could not open {selected_port_str}.\nCheck if it's used by another program.")
            except ValueError:
                messagebox.showerror("Error", "Invalid Port format. Use 'COMx'.")

        tk.Button(popup, text="CONNECT", bg="#4CAF50", fg="white", font=("Arial", 10, "bold"),
                  command=connect_action).pack(pady=15)

        # Pencere kapanana kadar kodu burada beklet
        self.wait_window(popup)

    # --- EKRAN 1: ANA MENÜ ---
    def show_main_menu(self):
        self.clear_screen()
        
        frame_menu = tk.LabelFrame(self.container, text="MAIN MENU", font=("Arial", 14, "bold"), padx=30, pady=30)
        frame_menu.pack(expand=True)

        tk.Button(frame_menu, text="1. Air Conditioner", font=("Arial", 12), width=25, height=2,
                  command=self.on_ac_clicked).pack(pady=10)
        
        tk.Button(frame_menu, text="2. Curtain Control", font=("Arial", 12), width=25, height=2,
                  command=self.on_curtain_clicked).pack(pady=10)
        
        tk.Button(frame_menu, text="3. Exit", font=("Arial", 12), width=25, height=2, bg="#f44336", fg="white",
                  command=self.quit_app).pack(pady=10)

    # --- GEÇİŞ MANTIĞI ---
    def on_ac_clicked(self):
        # Eğer bağlı değilse port sor
        if not self.ac_api.is_connected():
            self.ask_port_connection(self.ac_api, "Air Conditioner")
        
        # Bağlantı başarılı olduysa (veya zaten varsa) ekranı aç
        if self.ac_api.is_connected():
            self.show_ac_screen()

    def on_curtain_clicked(self):
        if not self.curtain_api.is_connected():
            self.ask_port_connection(self.curtain_api, "Curtain Control")
            
        if self.curtain_api.is_connected():
            self.show_curtain_screen()

    # --- EKRAN 2: KLİMA EKRANI ---
    def show_ac_screen(self):
        self.clear_screen()
        
        # Veri Alanı
        frame_info = tk.LabelFrame(self.container, text="System Monitor", font=("Arial", 10, "bold"))
        frame_info.pack(fill="x", pady=10)
        
        self.lbl_ac_amb = tk.Label(frame_info, text="Home Ambient Temperature: --.- ºC", font=("Arial", 11), anchor="w")
        self.lbl_ac_amb.pack(fill="x", padx=10, pady=5)
        
        self.lbl_ac_des = tk.Label(frame_info, text="Home Desired Temperature: --.- ºC", font=("Arial", 11), anchor="w")
        self.lbl_ac_des.pack(fill="x", padx=10, pady=5)
        
        self.lbl_ac_fan = tk.Label(frame_info, text="Fan Speed: --- rps", font=("Arial", 11, "bold"), anchor="w", fg="green")
        self.lbl_ac_fan.pack(fill="x", padx=10, pady=5)
        
        tk.Label(frame_info, text="-"*60).pack()
        tk.Label(frame_info, text=f"Connection Port: COM{self.ac_api.comPort} | Baudrate: {self.ac_api.baudRate}", fg="gray").pack(anchor="w", padx=10, pady=5)

        # Menü Alanı
        frame_ctrl = tk.LabelFrame(self.container, text="MENU", font=("Arial", 10, "bold"))
        frame_ctrl.pack(fill="both", expand=True, pady=10)
        
        tk.Button(frame_ctrl, text="1. Enter the desired temperature", anchor="w", padx=20, height=2,
                  command=self.ask_desired_temp).pack(fill="x", pady=5)
        
        tk.Button(frame_ctrl, text="2. Return", anchor="w", padx=20, height=2,
                  command=self.show_main_menu).pack(fill="x", pady=5)

    def ask_desired_temp(self):
        # Figure 18'deki input kutusu
        val = simpledialog.askfloat("Set Temperature", "Enter Desired Temp (10.0 - 50.0):", minvalue=10.0, maxvalue=50.0)
        if val is not None:
            if self.ac_api.setDesiredTemp(val):
                messagebox.showinfo("Success", f"Temperature set to {val} ºC")
            else:
                messagebox.showerror("Error", "Command failed! Device not responding.")

    # --- EKRAN 3: PERDE EKRANI ---
    def show_curtain_screen(self):
        self.clear_screen()
        
        # Veri Alanı
        frame_info = tk.LabelFrame(self.container, text="System Monitor", font=("Arial", 10, "bold"))
        frame_info.pack(fill="x", pady=10)
        
        self.lbl_cc_temp = tk.Label(frame_info, text="Outdoor Temperature: --.- ºC", font=("Arial", 11), anchor="w")
        self.lbl_cc_temp.pack(fill="x", padx=10, pady=2)
        
        self.lbl_cc_pres = tk.Label(frame_info, text="Outdoor Pressure: --.- hPa", font=("Arial", 11), anchor="w")
        self.lbl_cc_pres.pack(fill="x", padx=10, pady=2)
        
        self.lbl_cc_stat = tk.Label(frame_info, text="Curtain Status: --.- %", font=("Arial", 11, "bold"), anchor="w", fg="blue")
        self.lbl_cc_stat.pack(fill="x", padx=10, pady=2)
        
        self.lbl_cc_lght = tk.Label(frame_info, text="Light Intensity: ---.- Lux", font=("Arial", 11), anchor="w")
        self.lbl_cc_lght.pack(fill="x", padx=10, pady=2)

        tk.Label(frame_info, text="-"*60).pack()
        tk.Label(frame_info, text=f"Connection Port: COM{self.curtain_api.comPort} | Baudrate: {self.curtain_api.baudRate}", fg="gray").pack(anchor="w", padx=10, pady=5)

        # Menü Alanı
        frame_ctrl = tk.LabelFrame(self.container, text="MENU", font=("Arial", 10, "bold"))
        frame_ctrl.pack(fill="both", expand=True, pady=10)
        
        tk.Button(frame_ctrl, text="1. Enter the desired curtain status", anchor="w", padx=20, height=2,
                  command=self.ask_curtain_status).pack(fill="x", pady=5)
        
        tk.Button(frame_ctrl, text="2. Return", anchor="w", padx=20, height=2,
                  command=self.show_main_menu).pack(fill="x", pady=5)

    def ask_curtain_status(self):
        val = simpledialog.askfloat("Set Curtain", "Enter Desired Curtain % (0.0 - 100.0):", minvalue=0.0, maxvalue=100.0)
        if val is not None:
            if self.curtain_api.setCurtainStatus(val):
                messagebox.showinfo("Success", f"Curtain set to {val} %")
            else:
                messagebox.showerror("Error", "Command failed! Device not responding.")

    # --- SİSTEM DÖNGÜSÜ ---
    def update_data_loop(self):
        # 1. Bağlı olan sistemlerin verisini çek
        if self.ac_api.is_connected():
            self.ac_api.update()
        
        if self.curtain_api.is_connected():
            self.curtain_api.update()

        # 2. Eğer ilgili ekran açıksa (widgetlar varsa) yazıları güncelle
        try:
            # Klima Ekranı Açıksa
            if hasattr(self, 'lbl_ac_amb') and self.lbl_ac_amb.winfo_exists():
                self.lbl_ac_amb.config(text=f"Home Ambient Temperature: {self.ac_api.getAmbientTemp():.1f} ºC")
                self.lbl_ac_des.config(text=f"Home Desired Temperature: {self.ac_api.getDesiredTemp():.1f} ºC")
                self.lbl_ac_fan.config(text=f"Fan Speed: {self.ac_api.getFanSpeed()} rps")

            # Perde Ekranı Açıksa
            if hasattr(self, 'lbl_cc_temp') and self.lbl_cc_temp.winfo_exists():
                self.lbl_cc_temp.config(text=f"Outdoor Temperature: {self.curtain_api.getOutdoorTemp():.1f} ºC")
                self.lbl_cc_pres.config(text=f"Outdoor Pressure: {self.curtain_api.getOutdoorPress():.1f} hPa")
                self.lbl_cc_stat.config(text=f"Curtain Status: {self.curtain_api.getCurtainStatus():.1f} %")
                self.lbl_cc_lght.config(text=f"Light Intensity: {self.curtain_api.getLightIntensity():.1f} Lux")
        except:
            pass 

        # 1 saniye sonra tekrar çalış
        self.after(self.update_interval, self.update_data_loop)

    def quit_app(self):
        self.ac_api.close()
        self.curtain_api.close()
        self.destroy()

if __name__ == "__main__":
    app = HomeAutomationApp()
    app.mainloop()