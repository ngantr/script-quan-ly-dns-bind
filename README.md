# script-quan-ly-dns-bind
Script Bash tự động hóa cấu hình IP, tạo Domain, thiết lập DNS chính/phụ (Primary/Slave) và quản lý dịch vụ BIND trên Linux.

## Bước 1: Chuẩn bị môi trường

Đảm bảo máy chủ của bạn đã cài đặt dịch vụ BIND (`named`) và `NetworkManager`. Nếu chưa cài đặt, bạn có thể chạy nhanh lệnh sau:

```bash
sudo yum install bind bind-utils -y
sudo systemctl enable --now named
```
## Bước 2: Tải hoặc tạo file script
Tạo file script mới trên máy chủ:

```bash
nano setup_dns.sh
```
Copy toàn bộ mã nguồn script dán vào file. Lưu lại bằng tổ hợp phím Ctrl + O, nhấn Enter, sau đó thoát bằng Ctrl + X.

## Bước 3: Cấp quyền thực thi
Cấp quyền chạy cho file script bằng lệnh:

```bash
chmod +x setup_dns.sh
```
## Bước 4: Chạy chương trình
Do script cần can thiệp vào các file cấu hình hệ thống (/etc/named.conf) và card mạng, bạn bắt buộc phải chạy bằng quyền root:

```bash
sudo ./setup_dns.sh
```
## Bước 5: Hướng dẫn chi tiết các tính năng trong Menu
Sau khi khởi chạy script, giao diện menu chính sẽ hiển thị. Dưới đây là giải thích chi tiết chức năng của từng option:

🔹 1. Cấu hình IP

**Mục đích:** Thay đổi cấu hình card mạng đang hoạt động (NetworkManager) một cách nhanh chóng.


**Cách sử dụng:**

Chọn 1 (IP Tĩnh): Nhập địa chỉ IP muốn đặt (VD: 192.168.1.10). Hệ thống sẽ tự động gán subnet mask /24, đồng thời tự trỏ DNS về chính IP đó.

Chọn 2 (IP Động): Chuyển card mạng về chế độ nhận IP và DNS tự động qua DHCP (auto).

🔹 2. Cấu hình Domain

**Mục đích:** Khởi tạo một Zone thuận mới cho tên miền trên máy chủ BIND của bạn.

**Cách sử dụng:** Nhập tên miền (VD: hai.com) và địa chỉ IP của hosting DNS. Script sẽ tự động nối khai báo zone vào /etc/named.conf, tạo file zone thuận /var/named/hai.com.zone chứa các bản ghi chuẩn (SOA, NS, A, www, server), phân quyền chuẩn và khởi động lại dịch vụ.

🔹 3. Cấu hình Backup DNS (Primary & Backup Master/Slave)

**Mục đích:** Thiết lập hệ thống DNS dự phòng theo mô hình Master/Slave để đảm bảo tính sẵn sàng cao.

**Cách sử dụng:**

Chọn 1 (Trên máy Primary): Nhập IP của máy Backup và tên miền zone cần chia sẻ. Script sẽ tự động thêm cấu hình allow-transfer vào named.conf.

Chọn 2 (Trên máy Backup): Nhập IP của máy Primary và tên miền cần kéo dữ liệu. Script sẽ tự động cấu hình type slave, tạo thư mục nhận dữ liệu đồng bộ và kéo file zone từ máy chính sang.

🔹 4. Cấu hình Forward DNS

**Mục đích:** Thiết lập máy chủ chuyển tiếp truy vấn (forwarders) để phân giải các tên miền ngoài Internet.

**Cách sử dụng:** Nhập địa chỉ IP của máy chủ DNS chuyển tiếp (VD: 8.8.8.8 hoặc 1.1.1.1). Script sẽ tự động cấu hình vào file named.conf và khởi động lại dịch vụ.

🔹 5. Kiểm tra phân giải

**Mục đích:** Dùng lệnh nslookup để kiểm tra xem domain hoặc IP đã được phân giải thành công hay chưa.

**Cách sử dụng:** Nhập tên miền hoặc IP cần kiểm tra, script sẽ tự động ép trỏ tạm thời về 127.0.0.1 để test trực tiếp trên dịch vụ local.

🔹 6. Khởi động lại dịch vụ DNS (Restart named)

**Mục đích:** Khởi động lại dịch vụ named một cách an toàn.

**Tính năng phụ trợ:** Trước khi restart, script sẽ tự động chạy lệnh named-checkconf để kiểm tra lỗi cú pháp trong file cấu hình. Nếu cấu hình bị sai sót, script sẽ cảnh báo ngay lập tức để tránh làm sập dịch vụ DNS.

🔹 0. Thoát

**Mục đích:** Đóng chương trình quản lý và thoát khỏi script.
