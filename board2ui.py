import tkinter as tk
from tkinter import ttk, messagebox
import serial
import serial.tools.list_ports
import time
import threading

# --- PROJE AYARLARI ---
CMD_GET_CURTAIN = b'\x02'  # 2 (Perdeyi Sor)
CMD_GET_LIGHT   = b'\x08'  # 8 (Işığı Sor)

class CurtainControlApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Akıllı Perde - V3.1 (Raw Byte Modu)")
        self.root.geometry("500x550")
        self.root.resizable(False, False)
        
        self.ser = None
        self.is_connected = False

        # --- ARAYÜZ ---
        header_frame = tk.Frame(root, bg="#2c3e50", pady=15)
        header_frame.pack(fill="x")
        tk.Label(header_frame, text="ESOGU HOME AUTOMATION", font=("Arial", 14, "bold"), fg="white", bg="#2c3e50").pack()
        
        conn_frame = tk.LabelFrame(root, text="Bağlantı", padx=10, pady=10)
        conn_frame.pack(padx=10, pady=10, fill="x")

        tk.Label(conn_frame, text="COM Port:").grid(row=0, column=0, padx=5)
        self.port_entry = ttk.Entry(conn_frame, width=10)
        self.port_entry.insert(0, "COM1")
        self.port_entry.grid(row=0, column=1, padx=5)

        self.btn_connect = tk.Button(conn_frame, text="BAĞLAN", command=self.toggle_connection, bg="#27ae60", fg="white", width=12)
        self.btn_connect.grid(row=0, column=2, padx=10)
        
        self.lbl_status = tk.Label(conn_frame, text="Durum: Bağlı Değil", fg="red")
        self.lbl_status.grid(row=1, column=0, columnspan=3, pady=5)

        # Manuel Kontrol
        ctrl_frame = tk.LabelFrame(root, text="Manuel Kontrol", padx=10, pady=10)
        ctrl_frame.pack(padx=10, pady=5, fill="x")
        tk.Label(ctrl_frame, text="Hedef Pozisyon").pack()
        self.slider = tk.Scale(ctrl_frame, from_=0, to=63, orient="horizontal", length=350)
        self.slider.set(0)
        self.slider.pack(pady=5)
        tk.Button(ctrl_frame, text="AYARLA", command=self.send_curtain_command, bg="#e67e22", fg="white", width=20).pack(pady=10)

        # Canlı Veriler
        data_frame = tk.LabelFrame(root, text="Canlı Veriler", padx=10, pady=10)
        data_frame.pack(padx=10, pady=5, fill="x")
        
        self.lbl_curtain = tk.Label(data_frame, text="-- %", font=("Arial", 20, "bold"), fg="blue")
        self.lbl_curtain.pack(side="left", padx=20)
        
        self.lbl_light = tk.Label(data_frame, text="-- Lux", font=("Arial", 20, "bold"), fg="darkgreen")
        self.lbl_light.pack(side="right", padx=20)

        tk.Button(data_frame, text="GÜNCELLE", command=self.request_data, bg="#2980b9", fg="white", width=15).pack(side="bottom", pady=5)

        # Log Penceresi
        log_frame = tk.LabelFrame(root, text="İletişim Logları", padx=5, pady=5)
        log_frame.pack(padx=10, pady=5, fill="both", expand=True)
        self.log_text = tk.Text(log_frame, height=8, font=("Courier", 9))
        self.log_text.pack(fill="both", expand=True)

    def log(self, msg):
        self.log_text.insert(tk.END, msg + "\n")
        self.log_text.see(tk.END)

    def toggle_connection(self):
        if self.is_connected: self.disconnect()
        else: self.connect()

    def connect(self):
        port = self.port_entry.get()
        if not port: 
            messagebox.showerror("Hata", "Lütfen COM port girin!")
            return
        try:
            # V43/V44 PIC kodları için en kararlı ayarlar
            self.ser = serial.Serial(port, 9600, timeout=0.5)
            self.ser.dtr = False
            self.ser.rts = False
            self.is_connected = True
            self.btn_connect.config(text="KES", bg="#c0392b")
            self.lbl_status.config(text=f"Durum: Bağlı ({port})", fg="green")
            self.log(f"Bağlandı: {port}")
        except Exception as e:
            messagebox.showerror("Hata", f"{port} açılamadı!\n{e}")
            self.log(f"Hata: {e}")

    def disconnect(self):
        if self.ser: self.ser.close()
        self.is_connected = False
        self.btn_connect.config(text="BAĞLAN", bg="#27ae60")
        self.lbl_status.config(text="Durum: Bağlı Değil", fg="red")

    def send_curtain_command(self):
        if not self.is_connected: return
        val = self.slider.get()
        cmd = 0xC0 | val
        self.ser.write(bytes([cmd]))
        self.log(f">> Gönderildi: {cmd} (Hex: {hex(cmd)})")

    def request_data(self):
        if not self.is_connected: return
        threading.Thread(target=self._read_process, daemon=True).start()

    def _read_process(self):
        try:
            # ---------------------------------------------------------
            # 1. PERDE SORGUSU (Komut: 2)
            # ---------------------------------------------------------
            self.ser.reset_input_buffer()
            self.ser.write(CMD_GET_CURTAIN)
            time.sleep(0.1) # PIC'in cevaplaması için süre
            
            if self.ser.in_waiting > 0:
                # TEK BYTE OKU (Çünkü PIC tek byte sayı gönderiyor)
                raw_byte = self.ser.read(1)
                
                # Byte'ı Tam Sayıya Çevir (Örn: b']' -> 93)
                int_val = int.from_bytes(raw_byte, byteorder='big')
                
                self.log(f"<< Perde (Raw): {raw_byte} -> Sayı: {int_val}")
                self.root.after(0, lambda: self.lbl_curtain.config(text=f"{int_val} %"))
            else:
                self.log("<< Perde verisi gelmedi.")

            # ---------------------------------------------------------
            # 2. IŞIK SORGUSU (Komut: 8)
            # ---------------------------------------------------------
            time.sleep(0.1)
            self.ser.reset_input_buffer()
            self.ser.write(CMD_GET_LIGHT)
            time.sleep(0.1)
            
            if self.ser.in_waiting > 0:
                # TEK BYTE OKU
                raw_byte = self.ser.read(1)
                
                # Byte'ı Tam Sayıya Çevir (Örn: b'\x0e' -> 14)
                int_val = int.from_bytes(raw_byte, byteorder='big')
                
                self.log(f"<< Işık (Raw): {raw_byte} -> Sayı: {int_val}")
                self.root.after(0, lambda: self.lbl_light.config(text=f"{int_val}"))
            else:
                self.log("<< Işık verisi gelmedi.")

        except Exception as e:
            self.log(f"Okuma Hatası: {e}")

if __name__ == "__main__":
    root = tk.Tk()
    app = CurtainControlApp(root)
    root.mainloop()