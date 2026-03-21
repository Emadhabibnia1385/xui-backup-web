<div align="center">

# 🗄️ XUI Backup Hub
### مدیریت هوشمند بکاپ مرکزی پنل‌های X-UI

[![Python](https://img.shields.io/badge/Python-3.8+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Emadhabibnia1385/xui-backup-iran?style=for-the-badge&logo=github)](https://github.com/Emadhabibnia1385/xui-backup-iran/stargazers)

**یک راهکار ساده، سبک و قدرتمند برای بکاپ‌گیری خودکار از دیتابیس پنل‌های X-UI و 3X-UI در یک مکان مرکزی**

[نصب سریع](#-نصب-سریع) • [ویژگی‌ها](#-ویژگیها) • [معماری](#-معماری) • [پشتیبانی](#-پشتیبانی)

---

</div>

## 📖 درباره XUI Backup Hub

XUI Backup Hub یک سیستم بکاپ مرکزی برای پنل‌های X-UI و 3X-UI است. تمام سرورهای شما هر چند دقیقه یک‌بار فایل دیتابیس خود را به یک سرور مرکزی ارسال می‌کنند و از یک پنل وب ساده می‌توانید همه بکاپ‌ها را مشاهده و دانلود کنید.

### 🎯 مناسب برای:

- 🖥️ مدیران چندین سرور X-UI یا 3X-UI
- 🔐 کسانی که نگران از دست رفتن اطلاعات پنل هستند
- ⚡ افرادی که نیاز به بکاپ خودکار و بدون دردسر دارند
- 🏢 تیم‌ها و شرکت‌هایی که زیرساخت VPN مدیریت می‌کنند

---

## ✨ ویژگی‌ها

<table>
<tr>
<td width="25%" align="center">

### ⚡ بکاپ خودکار
✅ ارسال هر X دقیقه  
✅ بدون نیاز به SSH  
✅ مبتنی بر systemd  
✅ تشخیص خودکار مسیر DB

</td>
<td width="25%" align="center">

### 🌐 پنل وب
✅ رابط فارسی و زیبا  
✅ لاگین با یوزر و پسورد  
✅ دانلود مستقیم بکاپ  
✅ حذف IP از پنل

</td>
<td width="25%" align="center">

### 📦 مدیریت بکاپ
✅ دسته‌بندی بر اساس IP  
✅ نگهداری ۵ بکاپ آخر  
✅ حذف خودکار قدیمی‌ها  
✅ نمایش حجم و زمان

</td>
<td width="25%" align="center">

### 🔐 امنیت
✅ احراز هویت پنل وب  
✅ توکن اختصاصی آپلود  
✅ فقط فایل‌های .db قبول  
✅ بدون دسترسی عمومی

</td>
</tr>
</table>

---

## 🏗️ معماری

```
[سرور X-UI ۱]  ──┐
                  │  curl POST (هر N دقیقه)
[سرور X-UI ۲]  ──┼──────────────────────▶  [Backup Hub Server]
                  │                              │
[سرور X-UI ۳]  ──┘                         ذخیره .db
                                                 │
                                        پنل وب (port 8080)
                                     نمایش + دانلود + حذف
```

### جریان کار:
1. اسکریپت روی هر سرور X-UI فایل `x-ui.db` را پیدا می‌کند
2. هر N دقیقه یک کپی به سرور مرکزی ارسال می‌کند
3. سرور مرکزی فایل را با نام `backup__IP__TIME.db` ذخیره می‌کند
4. فقط ۵ بکاپ آخر هر IP نگه داشته می‌شود
5. از پنل وب می‌توانید بکاپ‌ها را مشاهده و دانلود کنید

---

## 🚀 نصب سریع

### روش اول: نصب خودکار (پیشنهادی) ⚡

تنها با **یک دستور** کل سیستم را نصب و راه‌اندازی کنید:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Emadhabibnia1385/xui-backup-iran/main/xui-backup-setup.sh)
```

> **نکته:** بعد از اجرا، منویی نمایش داده می‌شود. گزینه مناسب را انتخاب کنید.

---

### روش دوم: نصب دستی 🔧

#### مرحله ۱ — دانلود اسکریپت

```bash
curl -fsSL https://raw.githubusercontent.com/Emadhabibnia1385/xui-backup-iran/main/xui-backup-setup.sh -o xui-backup-setup.sh
chmod +x xui-backup-setup.sh
sudo bash xui-backup-setup.sh
```

#### یا اگر SFTP/SCP دارید:

```bash
# از کامپیوتر خود
scp xui-backup-setup.sh root@IP_SERVER:/root/

# روی سرور
sudo bash /root/xui-backup-setup.sh
```

---

## 📋 راهنمای نصب قدم به قدم

### ۱. نصب روی سرور مرکزی (Backup Hub)

اسکریپت را اجرا کنید و گزینه **1** را بزنید:

```
1) Install Backup Hub (central receiver server)
```

اطلاعات زیر از شما پرسیده می‌شود:

| پارامتر | توضیح | پیش‌فرض |
|---------|-------|---------|
| Upload Token | توکن امنیتی برای آپلود | `emad` |
| Port | پورت سرویس وب | `8080` |
| Web Username | نام کاربری پنل وب | `admin` |
| Web Password | رمز عبور پنل وب | — |

بعد از نصب:

```
Web panel URL : http://YOUR_IP:8080
Upload URL    : http://YOUR_IP:8080/upload?token=YOUR_TOKEN
```

---

### ۲. نصب روی سرورهای X-UI (Client)

اسکریپت را اجرا کنید و گزینه **2** را بزنید:

```
2) Install Client (X-UI sender server)
```

اطلاعات زیر از شما پرسیده می‌شود:

| پارامتر | توضیح | پیش‌فرض |
|---------|-------|---------|
| Hub IP | آدرس IP سرور مرکزی | — |
| Hub Port | پورت سرور مرکزی | `8080` |
| Upload Token | همان توکنی که در Hub تنظیم کردید | `emad` |
| Interval | فاصله ارسال بکاپ (دقیقه) | `2` |

---

## 🎮 مدیریت سرویس

از داخل اسکریپت گزینه **3** را بزنید، یا مستقیم:

```bash
# وضعیت Backup Hub
systemctl status backup-hub

# ری‌استارت Backup Hub
systemctl restart backup-hub

# وضعیت تایمر کلاینت
systemctl status xui-push-backup.timer

# ارسال دستی بکاپ
/usr/local/bin/xui-push-http.sh

# لاگ زنده Hub
journalctl -u backup-hub -f

# لاگ زنده کلاینت
journalctl -u xui-push-backup.service -f

# فایل لاگ کلاینت
tail -f /var/log/xui-push-http.log
```

---

## 📁 ساختار فایل‌ها

```
/root/backup-hub/
├── backup_hub.py              # سرور اصلی Python
└── data/
    ├── config.json            # توکن و اطلاعات لاگین
    └── backups/
        ├── backup__1_2_3_4__20260320_120000.db
        ├── backup__1_2_3_4__20260320_121500.db
        └── ...

/usr/local/bin/
└── xui-push-http.sh           # اسکریپت ارسال بکاپ

/etc/systemd/system/
├── backup-hub.service         # سرویس Hub
├── xui-push-backup.service    # سرویس کلاینت
└── xui-push-backup.timer      # تایمر کلاینت

/var/log/
└── xui-push-http.log          # لاگ ارسال‌ها
```

---

## 🔍 مسیرهای پشتیبانی شده DB

اسکریپت کلاینت به‌صورت خودکار فایل دیتابیس را در این مسیرها جستجو می‌کند:

```
/etc/x-ui/x-ui.db
/usr/local/x-ui/x-ui.db
/etc/3x-ui/x-ui.db
/usr/local/3x-ui/x-ui.db
/opt/x-ui/x-ui.db
/opt/3x-ui/x-ui.db
```

---

## 🐛 رفع مشکلات رایج

<details>
<summary><b>بکاپ ارسال نمی‌شود</b></summary>

```bash
# بررسی لاگ
tail -20 /var/log/xui-push-http.log

# تست دستی
/usr/local/bin/xui-push-http.sh

# بررسی دسترسی به سرور مرکزی
curl http://HUB_IP:8080
```

</details>

<details>
<summary><b>سرویس Hub اجرا نمی‌شود</b></summary>

```bash
# بررسی لاگ
journalctl -u backup-hub -n 50

# بررسی پورت
ss -tlnp | grep 8080

# اجرای دستی برای دیدن خطا
python3 /root/backup-hub/backup_hub.py
```

</details>

<details>
<summary><b>خطای "DB not found"</b></summary>

```bash
# پیدا کردن دستی مسیر DB
find / -name "x-ui.db" 2>/dev/null
```

مسیر پیدا شده را در `/usr/local/bin/xui-push-http.sh` اضافه کنید.

</details>

<details>
<summary><b>پنل وب باز نمی‌شود</b></summary>

```bash
# بررسی فایروال
ufw allow 8080

# بررسی وضعیت سرویس
systemctl status backup-hub
```

</details>

---

## 🤝 مشارکت در پروژه

مشارکت شما در بهبود XUI Backup Hub خوشامد است!

1. پروژه را Fork کنید
2. یک Branch جدید بسازید (`git checkout -b feature/amazing-feature`)
3. تغییرات خود را Commit کنید (`git commit -m 'Add amazing feature'`)
4. به Branch خود Push کنید (`git push origin feature/amazing-feature`)
5. یک Pull Request باز کنید

---

## 📞 پشتیبانی

<div align="center">

### راه‌های ارتباطی

[![Telegram](https://img.shields.io/badge/Developer-@EmadHabibnia-blue?style=for-the-badge&logo=telegram)](https://t.me/EmadHabibnia)
[![GitHub](https://img.shields.io/badge/GitHub-@Emadhabibnia1385-black?style=for-the-badge&logo=github)](https://github.com/Emadhabibnia1385)

</div>

- 💬 **تلگرام:** [@EmadHabibnia](https://t.me/EmadHabibnia)
- 🐙 **GitHub:** [@Emadhabibnia1385](https://github.com/Emadhabibnia1385)

---

## ⭐ حمایت از پروژه

اگر XUI Backup Hub برای شما مفید بود:

- ⭐ به پروژه Star بدهید
- 🔀 آن را Fork کنید
- 📢 در کانال‌های خود معرفی کنید
- 💡 باگ‌ها و ایده‌های خود را گزارش دهید

---

<div align="center">

**ساخته شده با ❤️ توسط [Emad Habibnia](https://t.me/EmadHabibnia)**

</div>
