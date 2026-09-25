#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo "Vui lòng chạy script bằng quyền root (sudo ./setup_dns.sh)!"
    exit 1
fi

# Kiểm tra chuỗi có phải địa chỉ IPv4 hợp lệ không
validate_ip() {
    local ip=$1
    local regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
    if [[ $ip =~ $regex ]]; then
        for octet in "${BASH_REMATCH[@]:1}"; do
            (( octet > 255 )) && return 1
        done
        return 0
    fi
    return 1
}

# Kiểm tra tên miền hợp lệ cơ bản
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then return 0; fi
    return 1
}

# 1. Cấu hình IP
config_ip() {
    echo "Chọn chế độ muốn cấu hình:"
    echo "1. Tĩnh."
    echo "2. Động."
    read -p "Lựa chọn: " mode

    CONN_NAME=$(nmcli -t -f NAME connection show --active | head -n 1)
    if [ -z "$CONN_NAME" ]; then
        echo "Không tìm thấy kết nối mạng active nào!"
        return
    fi

    case $mode in
        1)
            read -p "Nhập địa chỉ IP cho hệ thống: " ip_addr
            if ! validate_ip "$ip_addr"; then
                echo "Địa chỉ IP không hợp lệ!"
                return
            fi
            nmcli con mod "$CONN_NAME" ipv4.addresses "$ip_addr/24" ipv4.dns "$ip_addr" ipv4.method manual > /dev/null 2>&1
            nmcli con up "$CONN_NAME" > /dev/null 2>&1
            echo "=> Đã cấu hình IP tĩnh và trỏ DNS về $ip_addr thành công!"
            ;;
        2)
            nmcli con mod "$CONN_NAME" ipv4.method auto ipv4.dns "" > /dev/null 2>&1
            nmcli con up "$CONN_NAME" > /dev/null 2>&1
            echo "=> Đã cấu hình nhận IP và DNS tự động!"
            ;;
        *)
            echo "Lựa chọn không hợp lệ!"
            ;;
    esac
}

# 2. Cấu hình Domain
config_domain() {
    read -p "Nhập tên miền muốn tạo (VD: hai.com): " domain
    if ! validate_domain "$domain"; then
        echo "Tên miền không hợp lệ!"
        return
    fi

    read -p "Nhập IP của hosting DNS (VD: 172.16.1.3): " dns_ip
    if ! validate_ip "$dns_ip"; then
        echo "Địa chỉ IP không hợp lệ!"
        return
    fi

    if grep -q "zone \"$domain\"" /etc/named.conf; then
        echo "Zone $domain đã tồn tại trong /etc/named.conf!"
        return
    fi

    echo "zone \"$domain\" IN {
        type master;
        file \"$domain.zone\";
        allow-update { none; };
    };" >> /etc/named.conf

    zone_file="/var/named/$domain.zone"
    cat > "$zone_file" <<EOF
\$TTL 86400
@   IN  SOA     server.$domain. root.$domain. (
    2026092101  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
@       IN  NS      server.$domain.
@       IN  A       $dns_ip
server  IN  A       $dns_ip
www     IN  A       $dns_ip
EOF

    chown root:named "$zone_file"
    chmod 640 "$zone_file"

    systemctl restart named > /dev/null 2>&1
    echo "=> Đã tạo xong tên miền $domain với IP $dns_ip"
}

# 3. Cấu hình Backup DNS (Primary & Backup Master/Slave)
config_backup_dns() {
    echo "Chọn loại server muốn cấu hình:"
    echo "1. Primary"
    echo "2. Backup"
    read -p "Lựa chọn: " server_type

    case $server_type in
        1)
            read -p "Nhập địa chỉ máy chủ backup: " backup_ip
            if ! validate_ip "$backup_ip"; then
                echo "Địa chỉ IP không hợp lệ!"
                return
            fi

            read -p "Nhập tên miền zone cần cấp quyền (VD: sgu.edu.vn): " target_domain
            if [ -z "$target_domain" ]; then
                echo "Tên miền không được để trống!"
                return
            fi

            if grep -q "zone \"$target_domain\"" /etc/named.conf; then
                if ! grep -A 4 "zone \"$target_domain\"" /etc/named.conf | grep -q "allow-transfer"; then
                    sed -i "/zone \"$target_domain\"/,/};/ s|file .*|&\n    allow-transfer { $backup_ip; };|" /etc/named.conf
                    echo "=> Đã tự động thêm allow-transfer vào zone $target_domain thành công!"
                else
                    sed -i "/zone \"$target_domain\"/,/};/ s/allow-transfer.*/allow-transfer { $backup_ip; };/" /etc/named.conf
                    echo "=> Đã cập nhật lại IP allow-transfer cho zone $target_domain!"
                fi
            else
                echo "Không tìm thấy zone $target_domain trong file /etc/named.conf!"
                return
            fi

            systemctl restart named > /dev/null 2>&1
            echo "=> Đã khởi động lại dịch vụ trên Primary thành công!"
            ;;
        2)
            read -p "Nhập địa chỉ IP máy chủ primary: " primary_ip
            if ! validate_ip "$primary_ip"; then
                echo "Địa chỉ IP không hợp lệ!"
                return
            fi

            read -p "Nhập tên miền cần cấu hình backup (VD: sgu.edu.vn): " backup_domain
            if [ -z "$backup_domain" ]; then
                echo "Tên miền không được để trống!"
                return
            fi

            if grep -q "zone \"$backup_domain\"" /etc/named.conf; then
                sed -i "/zone \"$backup_domain\"/,/};/ s/masters\s*\{[^}]*\};/masters { $primary_ip; };/" /etc/named.conf
            else
                cat >> /etc/named.conf <<EOF

zone "$backup_domain" IN {
    type slave;
    masters { $primary_ip; };
    file "slaves/$backup_domain.zone";
};
EOF
            fi

            mkdir -p /var/named/slaves
            chown -R root:named /var/named/slaves
            chmod 770 /var/named/slaves
            rm -f /var/named/slaves/$backup_domain.zone

            systemctl restart named > /dev/null 2>&1
            echo "=> Đã cấu hình và làm mới dữ liệu Backup thành công cho tên miền $backup_domain!"
            ;;
        *)
            echo "Lựa chọn không hợp lệ!"
            ;;
    esac
}

# 4. Cấu hình forward DNS
config_forward_dns() {
    read -p "Nhập địa chỉ máy chủ muốn chuyển tiếp truy vấn: " forward_ip
    if ! validate_ip "$forward_ip"; then
        echo "Địa chỉ IP không hợp lệ!"
        return
    fi

    sed -i '/forwarders/d' /etc/named.conf
    sed -i '/forward only/d' /etc/named.conf

    sed -i "/options {/a \    forwarders { $forward_ip; };\n    forward only;" /etc/named.conf

    echo "=> Đã cập nhật IP forwarders thành công thành: $forward_ip"
    systemctl restart named > /dev/null 2>&1
    echo "=> Dịch vụ DNS đã được khởi động lại thành công!"
}

# 5. Chức năng kiểm tra phân giải (nslookup)
run_nslookup() {
    read -p "Nhập tên miền (hoặc IP) cần kiểm tra: " target_name
    if [ -z "$target_name" ]; then
        echo "Lỗi: Bạn chưa nhập thông tin!"
        return
    fi
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
    echo "--- Kết quả nslookup cho $target_name ---"
    nslookup "$target_name"
    echo "----------------------------------------"
}

# 6. Khởi động lại dịch vụ named
restart_dns() {
    echo "Đang kiểm tra lỗi cấu hình BIND (named-checkconf)..."
    if named-checkconf; then
        systemctl restart named
        if [ $? -eq 0 ]; then
            echo "=> Đã khởi động lại dịch vụ named thành công!"
        else
            echo "=> Lỗi: Không thể khởi động lại dịch vụ named!"
        fi
    else
        echo "=> Phát hiện lỗi trong file cấu hình BIND. Vui lòng kiểm tra lại!"
    fi
}

# ----------- Menu chính -----------
show_menu() {
    echo "=============================="
    echo "    QUẢN LÝ MẠNG VÀ DNS BIND    "
    echo "=============================="
    echo "1. Cấu hình IP."
    echo "2. Cấu hình Domain."
    echo "3. Cấu hình Backup DNS."
    echo "4. Cấu hình forward DNS."
    echo "5. Kiểm tra phân giải."
    echo "6. Khởi động lại dịch vụ DNS (Restart named)."
    echo "0. Thoát"
}

while true; do
    show_menu
    read -p "Lựa chọn của bạn: " choice
    case $choice in
        1) config_ip ;;
        2) config_domain ;;
        3) config_backup_dns ;;
        4) config_forward_dns ;;
        5) run_nslookup ;;
        6) restart_dns ;;
        0)
            echo "Thoát chương trình."
            exit 0
            ;;
        *)
            echo "Lựa chọn không hợp lệ, vui lòng chọn lại!"
            ;;
    esac
    echo ""
done