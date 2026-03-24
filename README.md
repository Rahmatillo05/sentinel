# Sentinel

Nginx serverlar uchun xavfsizlik monitoring tizimi. Fail2ban orqali hujumlarni aniqlaydi, bloklaydi va Telegram'ga xabar beradi.

## Qanday ishlaydi

```
Internet → Nginx → Sentinel (Fail2ban) → Ban + Telegram xabar
```

Sentinel Nginx access loglarini kuzatadi. Shubhali so'rov aniqlansa — IP bloklanadi va sizga Telegram orqali xabar keladi.

## Tezkor o'rnatish

```bash
git clone https://github.com/Rahmatillo05/sentinel.git
cd sentinel
sudo bash install.sh
```

Script sizdan 3 narsa so'raydi:
- Nginx to'g'ridan-to'g'ri yoki proxy ortidami
- Telegram bot token va chat ID
- Whitelist IP'lar (ixtiyoriy)

Qolgan hammasi avtomatik — OS, firewall, paketlar o'zi aniqlanadi.

## Nginx sozlash

O'rnatishdan keyin Nginx configga qo'shish kerak:

**nginx.conf — http {} ichiga:**
```nginx
http {
    include /etc/nginx/sentinel-log-format.conf;
    include /etc/nginx/sentinel-security.conf;
    # Agar proxy ortida bo'lsa:
    # include /etc/nginx/sentinel-realip.conf;
}
```

**Har bir server {} ichiga:**
```nginx
server {
    access_log /var/log/nginx/example.com_access.log sentinel;

    if ($sentinel_blocked) {
        return 403;
    }
}
```

Keyin:
```bash
nginx -t && nginx -s reload
```

## Test

```bash
sudo bash test.sh
```

Boshqa qurilmadan (o'z IP'ingizdan emas!) test qilish:
```bash
curl -k https://YOUR_DOMAIN/.env                          # scanner
curl -k 'https://YOUR_DOMAIN/?id=1+UNION+SELECT+1,2,3'   # exploit
curl -k -A 'sqlmap/1.5' https://YOUR_DOMAIN/              # botnet
```

## Nimalarni aniqlaydi

| Jail | Hujum turi | Trigger | Ban |
|------|-----------|---------|-----|
| sentinel-scanner | `.env`, `.git`, wp-admin, phpmyadmin, actuator, cgi-bin | 3 urinish | 24 soat |
| sentinel-exploit | SQLi, XSS, RCE, SSRF, Log4Shell, web shell | 1 urinish | 7 kun |
| sentinel-botnet | sqlmap, nikto, python-requests, bo'sh user-agent | 1 urinish | 7 kun |
| sentinel-ratelimit | 1 daqiqada 100+ ta 4xx xato | 100 urinish | 1 soat |
| sentinel-bruteforce | /login, /auth ga takroriy POST | 15 urinish | 1 soat |
| sentinel-recidive | Qayta-qayta bloklangan IP | 3 ta ban | 1 hafta → oshib boradi |
| sshd | SSH brute force | 5 urinish | 24 soat |

## Qo'llab-quvvatlanadigan tizimlar

- **OS:** Debian 12/13, Ubuntu 22.04+, CentOS Stream 9, AlmaLinux 9, Rocky Linux 9
- **Firewall:** nftables, firewalld, iptables (avtomatik aniqlanadi)
- **Arxitektura:** to'g'ridan-to'g'ri Nginx yoki HAProxy/LB ortida

## Foydali buyruqlar

```bash
fail2ban-client status                                 # umumiy holat
fail2ban-client status sentinel-scanner                # bitta jail
fail2ban-client banned                                 # bloklangan IP'lar
fail2ban-client set sentinel-scanner unbanip 1.2.3.4   # IP ochish
fail2ban-client unban --all                            # hammasini ochish
```

## O'chirish

```bash
sudo bash uninstall.sh
```

## Litsenziya

MIT
