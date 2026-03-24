#!/bin/bash
set -e

echo "=== Удаление симуляции активности ==="

# 1. Останавливаем getty и убираем автологин
echo "Убираем автологин..."
rm -f /etc/systemd/system/getty@tty1.service.d/override.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
systemctl daemon-reload
systemctl restart getty@tty1.service
echo "Автологин отключён"

# 2. Убираем nullok из PAM если мы его добавляли
if grep -q "nullok" /etc/pam.d/login; then
    sed -i 's/pam_unix.so nullok/pam_unix.so/' /etc/pam.d/login
    echo "PAM nullok убран"
fi

# 3. Удаляем скрипты
echo "Удаляем скрипты..."
rm -f /usr/local/bin/genact
rm -f /usr/local/bin/start-activity-sim.sh
echo "Скрипты удалены"

# 4. Убиваем tmux сессию если запущена
tmux kill-session -t activity 2>/dev/null && echo "tmux сессия остановлена" || true

# 5. Удаляем пользователя display
if id "display" &>/dev/null; then
    echo "Удаляем пользователя display..."
    pkill -u display 2>/dev/null || true
    sleep 1
    deluser --remove-home display
    echo "Пользователь display удалён"
else
    echo "Пользователь display не найден"
fi

echo ""
echo "=== УДАЛЕНИЕ ЗАВЕРШЕНО ==="
echo "Рекомендуется перезагрузка:"
echo "   sudo reboot"
