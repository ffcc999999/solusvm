#!/bin/bash

PROXY_PATH="/opt/marzban/proxy_marzban.py"
SYSCTL_FILE="/etc/sysctl.d/99-proxy_marzban.conf"
SERVICE_FILE="/etc/systemd/system/proxy_marzban.service"

cat <<'EOF' > $PROXY_PATH
import socket
import threading

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 8080
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 8000

def handle(client_sock, target_host, target_port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as remote_sock:
        remote_sock.connect((target_host, target_port))

        def forward(src, dst):
            try:
                while True:
                    data = src.recv(4096)
                    if not data:
                        break
                    dst.sendall(data)
            except Exception:
                pass

        t1 = threading.Thread(target=forward, args=(client_sock, remote_sock))
        t2 = threading.Thread(target=forward, args=(remote_sock, client_sock))
        t1.start()
        t2.start()
        t1.join()
        t2.join()

def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.bind((LISTEN_HOST, LISTEN_PORT))
        server.listen(100)
        print(f'Proxy listening on {LISTEN_HOST}:{LISTEN_PORT} -> {TARGET_HOST}:{TARGET_PORT}')
        while True:
            client_sock, addr = server.accept()
            threading.Thread(target=handle, args=(client_sock, TARGET_HOST, TARGET_PORT), daemon=True).start()

if __name__ == '__main__':
    main()
EOF


cat <<EOF | sudo tee $SYSCTL_FILE
fs.file-max = 1000000
net.ipv4.ip_forward = 1
net.core.somaxconn = 8192
EOF

sudo sysctl --system

cat <<EOF | sudo tee $SERVICE_FILE
[Unit]
Description=Simple TCP Proxy for Marzban 8000
After=network.target

[Service]
User=$USERNAME
WorkingDirectory=$(dirname "$PROXY_PATH")
ExecStart=/usr/bin/python3 $PROXY_PATH
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "[INFO] Systemd unit created: $SERVICE_FILE"

sudo systemctl daemon-reload
sudo systemctl enable proxy_marzban
sudo systemctl restart proxy_marzban

echo "[INFO] Service proxy_marzban up and running!"

sudo systemctl status proxy_marzban --no-pager

echo "[SUCCESS] Done!"
