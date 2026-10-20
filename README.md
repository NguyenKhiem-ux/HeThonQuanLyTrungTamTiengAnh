# Hệ thống quản lý trung tâm tiếng Anh

Ứng dụng MVP chạy trên Flutter Web, sử dụng Firebase Authentication để xác thực và Cloud Firestore để lưu hồ sơ, vai trò người dùng.

## Chạy ứng dụng

```powershell
flutter pub get
flutter run -d chrome
```

- Đăng nhập thông thường: trang gốc của ứng dụng.
- Đăng nhập Admin: `/#/admin/login`, ví dụ `http://localhost:5000/#/admin/login`.
- Học viên đăng ký mới được kích hoạt ngay. Giáo viên và Nhân viên tư vấn phải chờ quản trị viên phê duyệt.

## Tài khoản demo

| Email | Vai trò | Trạng thái |
|---|---|---|
| `admin.demo@example.com` | Admin | active |
| `teacher.demo@example.com` | Giáo viên | active |
| `consultant.demo@example.com` | Nhân viên tư vấn | active |
| `student.demo@example.com` | Học viên | active |
DEMO_ACCOUNT_PASSWORD='ThayBangMatKhauDemoManh123!'

Mật khẩu không được lưu trong source. Sau lần seed tạo mới tài khoản, xem mật khẩu trong `DEMO_ACCOUNTS.local.md`; tệp này đã được `.gitignore`. Nếu tài khoản đã tồn tại, script giữ nguyên mật khẩu và không thể truy xuất lại mật khẩu cũ.

## Khởi tạo tài khoản demo

Yêu cầu Node.js 22 trở lên và tài khoản/service account có quyền quản trị Firebase. Lưu private key bên ngoài repository, sau đó chạy bằng PowerShell:

```powershell
cd scripts
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\secure\firebase-service-account.json'
$env:FIREBASE_PROJECT_ID='hethongquanlytrungtamtienganh'
$env:DEMO_ACCOUNT_PASSWORD='mat-khau-demo-toi-thieu-12-ky-tu'
npm run seed-demo
```

Để chỉ tạo Admin demo trước, có thể thêm:

```powershell
$env:DEMO_SEED_TARGET='admin'
```

Mật khẩu dưới 12 ký tự bị từ chối mặc định. Chỉ trong môi trường demo, đặt `ALLOW_WEAK_DEMO_PASSWORD=true` để cho phép tối thiểu 6 ký tự rồi đổi mật khẩu ngay sau khi trình diễn.

Script kiểm tra Project ID, không đổi mật khẩu hay ghi đè hồ sơ đã có, và có thể chạy lại. Admin duy nhất được ghi bằng UID trong document cố định `system/admin`; nếu document này đã trỏ đến Admin khác, script dừng thay vì tạo Admin thứ hai.

## Firestore Rules

Mở Firebase Console → Firestore Database → Rules, dán nội dung `firestore.rules` và chọn **Publish**. Rules cho phép client tạo hồ sơ `student/active`, `teacher/pending` hoặc `consultant/pending`, nhưng cấm tạo Admin và cấm tự sửa `role`/`status`.

UID cố định trong `system/admin`, hồ sơ `admin/active` và Rules cùng bảo vệ luồng ứng dụng. Firebase Console và Admin SDK có đặc quyền bỏ qua Rules, vì vậy người có quyền quản trị Firebase vẫn phải bảo vệ thông tin xác thực và không sửa dữ liệu này tùy ý.
