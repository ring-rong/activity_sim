#!/bin/bash
set -e

echo "=== Полная настройка симуляции активности (с рандомом + автологином) ==="

# 1. Создаём пользователя display
if ! id "display" &>/dev/null; then
    adduser --disabled-password --gecos "" display
    echo "Пользователь display создан"
else
    echo "Пользователь display уже существует"
fi

# Убеждаемся что shell не заблокирован
usermod -s /bin/bash display

# Убираем пароль и разрешаем вход с пустым
passwd -d display

# 2. Переключаем на немецкое зеркало и устанавливаем пакеты
tee /etc/apt/sources.list.d/ubuntu.sources << 'EOF'
Types: deb
URIs: http://de.archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://de.archive.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

apt update -qq
apt install -y tmux curl wget

# 3. Установка genact
echo "Устанавливаем genact..."
curl -L -o /usr/local/bin/genact \
    "https://github.com/svenstaro/genact/releases/download/v1.5.1/genact-1.5.1-x86_64-unknown-linux-musl"
chmod +x /usr/local/bin/genact
echo "genact установлен: $(genact --version)"

# 4. Основной скрипт с ротацией модулей
cat > /usr/local/bin/start-activity-sim.sh << 'INNER'
#!/bin/bash

SESSION="activity"
MODULES=("ansible" "bootlog" "cargo" "cc" "composer" "docker_build" "download" "kernel_compile" "memdump" "mkinitcpio" "rkhunter" "terraform" "weblog")

launch_session() {
    tmux kill-session -t $SESSION 2>/dev/null || true
    sleep 1
    tmux new-session -d -s $SESSION

    NUM_PANES=$((RANDOM % 3 + 2))
    selected=()
    while [ ${#selected[@]} -lt $NUM_PANES ]; do
        mod=${MODULES[$((RANDOM % ${#MODULES[@]}))]}
        if [[ ! " ${selected[*]} " =~ " ${mod} " ]]; then
            selected+=("$mod")
        fi
    done

    tmux send-keys -t $SESSION:0 "genact --modules ${selected[0]} --speed-factor $((RANDOM % 5 + 1))" Enter

    if [ $NUM_PANES -ge 2 ]; then
        tmux split-window -h -t $SESSION
        tmux send-keys -t $SESSION:0.1 "genact --modules ${selected[1]} --speed-factor $((RANDOM % 5 + 1))" Enter
    fi

    if [ $NUM_PANES -ge 3 ]; then
        tmux split-window -v -t $SESSION:0.1
        tmux send-keys -t $SESSION:0.2 "genact --modules ${selected[2]} --speed-factor $((RANDOM % 5 + 1))" Enter
    fi

    if [ $NUM_PANES -eq 4 ]; then
        tmux split-window -v -t $SESSION:0
        tmux send-keys -t $SESSION:0.3 "genact --modules ${selected[3]} --speed-factor $((RANDOM % 5 + 1))" Enter
    fi

    tmux select-layout -t $SESSION tiled
}

rotate_loop() {
    while true; do
        WAIT=$((RANDOM % 1201 + 600))
        sleep $WAIT
        launch_session
    done
}

# Первый запуск
launch_session

# Ротация в фоне
rotate_loop &

# Присоединяемся к сессии
exec tmux attach-session -t $SESSION
INNER
chmod +x /usr/local/bin/start-activity-sim.sh

# 5. Автологин + автозапуск
mkdir -p /home/display
cat > /home/display/.bash_profile << 'PROFILE'
if [[ $(tty) == /dev/tty1 ]]; then
    exec /usr/local/bin/start-activity-sim.sh
fi
PROFILE
chown display:display /home/display/.bash_profile

# 6. Настройка автологина через getty
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \u' --noclear --autologin display %I $TERM
GETTY

# 7. Разрешаем PAM логин с пустым паролем
if ! grep -q "nullok" /etc/pam.d/login; then
    sed -i 's/pam_unix.so/pam_unix.so nullok/' /etc/pam.d/login
    echo "PAM nullok добавлен"
fi

# Убираем ошибку pam_lastlog если модуль отсутствует
if [ ! -f /usr/lib/security/pam_lastlog.so ]; then
    sed -i '/pam_lastlog/d' /etc/pam.d/login
    echo "pam_lastlog убран"
fi

systemctl daemon-reload
systemctl restart getty@tty1.service

echo ""
echo "=== ВСЁ НАСТРОЕНО! ==="
echo "Теперь просто выполни:"
echo "   sudo reboot"
