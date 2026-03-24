# Sentinel — Server Security Monitor

Nginx serverlar uchun Fail2ban asosidagi xavfsizlik monitoring tizimi.
Hujumlarni aniqlaydi, IP'larni bloklaydi va Telegram orqali xabar beradi.

## Imkoniyatlari

- **23 xil hujum turini aniqlash** — SQLi, XSS, RCE, SSRF, Log4Shell, scanner, brute force
- **Avtomatik OS/firewall aniqlash** — Debian 13 (nftables), CentOS 9 (firewalld), iptables
- **HAProxy/LB ortida ishlash** — proxy va to'g'ridan-to'g'ri Nginx arxitekturalari
- **SEO himoyasi** — Google, Bing, Yandex botlari bloklanmaydi (IP whitelist + UA filter)
- **Telegram bildirishnomalar** — ban/unban, kunlik hisobot, health check
- **Progressiv ban** — qayta offenderlar uchun 1 hafta → 1 oy → doimiy
- **Xavfsiz reload** — Nginx 10 sekundda bir reload (websocket himoyasi)

## Tizim talablari

- **OS:** Debian 12/13, Ubuntu 22.04+, CentOS Stream 9, AlmaLinux 9, Rocky Linux 9
- **Nginx** o'rnatilgan bo'lishi kerak
- **Root** huquqi
- **Telegram bot** (token va chat ID)

## O'rnatish

```bash
git clone <repo-url> sentinel
cd sentinel
sudo bash install.sh
```

Script so'raydi:
1. Arxitektura — to'g'ridan-to'g'ri yoki proxy ortida
2. Telegram BOT_TOKEN va CHAT_ID
3. Qo'shimcha whitelist IP'lar (ixtiyoriy)

## Nginx konfiguratsiya

Install'dan keyin Nginx'ga 3 ta o'zgartirish kerak.

**1. `nginx.conf` — http {} blokiga:**

```nginx
http {
    # Sentinel
    include /etc/nginx/sentinel-log-format.conf;
    include /etc/nginx/sentinel-security.conf;
    include /etc/nginx/sentinel-realip.conf;   # faqat proxy ortida

    # ... mavjud konfiguratsiya ...
}
```

**2. Har bir `server {}` blokiga:**

```nginx
server {
    access_log /var/log/nginx/example.com_access.log sentinel;

    if ($sentinel_blocked) {
        return 403;
    }

    # ... mavjud konfiguratsiya ...
}
```

**3. Tekshirish va reload:**

```bash
nginx -t && nginx -s reload
```

## Test

```bash
sudo bash test.sh
```

7 bosqichli avtomatik test: Fail2ban holati, jaillar, log format, regex, ban/unban, Telegram, xavfsizlik.

## Hujum simulyatsiya

Boshqa qurilmadan (o'z IP'ingizdan EMAS):

```bash
# Scanner (3 ta kerak → ban):
curl -k https://YOUR_DOMAIN/.env
curl -k https://YOUR_DOMAIN/.git/config
curl -k https://YOUR_DOMAIN/wp-admin/

# Exploit (1 ta yetarli → ban):
curl -k 'https://YOUR_DOMAIN/?id=1+UNION+SELECT+1,2,3'

# Botnet (1 ta yetarli → ban):
curl -k -A 'sqlmap/1.5' https://YOUR_DOMAIN/
```

## Foydali buyruqlar

```bash
# Holat
fail2ban-client status                    # umumiy
fail2ban-client status sentinel-scanner   # bitta jail
fail2ban-client banned                    # barcha bloklangan IP'lar

# Boshqarish
fail2ban-client set sentinel-scanner unbanip 1.2.3.4   # IP ochish
fail2ban-client unban --all                             # hammasini ochish

# Loglar
cat /etc/nginx/sentinel-deny.map          # bloklangan IP'lar
cat /var/log/sentinel/sentinel.log        # Sentinel logi
tail -f /var/log/fail2ban.log             # Fail2ban logi
```

## Jaillar

| Jail | Nima aniqlaydi | maxretry | bantime |
|------|---------------|----------|---------|
| sentinel-scanner | `.env`, `.git`, wp-admin, phpmyadmin, actuator, cgi-bin | 3 | 24 soat |
| sentinel-exploit | SQLi, XSS, RCE, SSRF, Log4Shell, web shell | 1 | 7 kun |
| sentinel-botnet | sqlmap, nikto, python-requests, bo'sh UA | 1 | 7 kun |
| sentinel-ratelimit | 1 daqiqada 50+ ta 4xx javob | 50 | 1 soat |
| sentinel-bruteforce | /login, /auth ga ko'p POST | 10 | 1 soat |
| sentinel-recidive | Qayta bloklangan IP'lar | 3 ban | 1 hafta → oshib boradi |
| sshd | SSH brute force | 3 | 24 soat |

## Fayl joylashuvi

```
/etc/sentinel/                  # Konfiguratsiya
  sentinel.conf                 # Token, chat_id (chmod 600)
  whitelist.conf                # Qo'lda whitelist
  whitelist-searchengines.conf  # Avtomatik (Google/Bing/Yandex IP)

/etc/fail2ban/filter.d/         # Filterlar
  sentinel-scanner.conf
  sentinel-exploit.conf
  sentinel-botnet.conf
  sentinel-ratelimit.conf
  sentinel-bruteforce.conf

/etc/fail2ban/jail.d/           # Jaillar
  sentinel-jails.conf

/etc/fail2ban/action.d/         # Actionlar
  sentinel-nginx-block.conf
  sentinel-telegram.conf

/etc/nginx/                     # Nginx config
  sentinel-log-format.conf
  sentinel-security.conf
  sentinel-realip.conf          # faqat proxy
  sentinel-deny.map             # bloklangan IP'lar

/usr/local/bin/                 # Scriptlar
  sentinel-notify.sh
  sentinel-whitelist-update.sh
  sentinel-daily-report.sh
  sentinel-health-check.sh
  sentinel-reload-timer.sh
```

## O'chirish

```bash
sudo bash uninstall.sh
```

Nginx konfiguratsiyasidan sentinel qatorlarni qo'lda olib tashlang (script ko'rsatma beradi).

## Arxitektura

```
Internet → [HAProxy] → Nginx → App
                          │
                     Sentinel log
                          │
                       Fail2ban
                       ├── Filter (regex)
                       ├── Ban (nftables/firewalld + nginx deny map)
                       └── Notify (Telegram)
```

**Proxy ortida:** `nginx-block-map` orqali Nginx darajasida bloklash
**To'g'ridan-to'g'ri:** kernel firewall + `nginx-block-map` ikki qavat himoya

## Litsenziya

MIT
