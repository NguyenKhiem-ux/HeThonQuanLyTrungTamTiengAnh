'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  applicationDefault,
  deleteApp,
  initializeApp,
} = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'hethongquanlytrungtamtienganh';
const DEMO_ACCOUNTS = [
  {
    email: 'admin.demo@example.com',
    fullName: 'Admin Demo',
    role: 'admin',
  },
  {
    email: 'teacher.demo@example.com',
    fullName: 'Giáo viên Demo',
    role: 'teacher',
  },
  {
    email: 'consultant.demo@example.com',
    fullName: 'Tư vấn viên Demo',
    role: 'consultant',
  },
  {
    email: 'student.demo@example.com',
    fullName: 'Học viên Demo',
    role: 'student',
  },
];

function readConfiguration() {
  if (process.env.FIREBASE_PROJECT_ID !== EXPECTED_PROJECT_ID) {
    throw new Error(
      `FIREBASE_PROJECT_ID phải là ${EXPECTED_PROJECT_ID}. Script chưa thay đổi dữ liệu.`,
    );
  }

  const password = process.env.DEMO_ACCOUNT_PASSWORD;
  const allowWeakPassword = process.env.ALLOW_WEAK_DEMO_PASSWORD === 'true';
  const minimumLength = allowWeakPassword ? 6 : 12;
  if (!password || password.length < minimumLength) {
    throw new Error(
      `DEMO_ACCOUNT_PASSWORD phải có ít nhất ${minimumLength} ký tự.`,
    );
  }
  if (allowWeakPassword) {
    console.warn('Đang cho phép mật khẩu demo yếu theo yêu cầu tường minh.');
  }

  const target = process.env.DEMO_SEED_TARGET || 'all';
  if (target !== 'all' && target !== 'admin') {
    throw new Error('DEMO_SEED_TARGET chỉ nhận giá trị all hoặc admin.');
  }
  return { password, target };
}

async function findOrCreateAuthUser(auth, account, password) {
  try {
    const user = await auth.getUserByEmail(account.email);
    return { user, created: false };
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }

  const user = await auth.createUser({
    email: account.email,
    emailVerified: true,
    displayName: account.fullName,
    password,
  });
  return { user, created: true };
}

function assertMatchingProfile(snapshot, account, uid) {
  if (!snapshot.exists) return false;

  const data = snapshot.data();
  const expected = {
    uid,
    fullName: account.fullName,
    email: account.email,
    role: account.role,
    status: 'active',
  };
  for (const [field, value] of Object.entries(expected)) {
    if (data[field] !== value) {
      throw new Error(
        `Hồ sơ users/${uid} đã tồn tại nhưng trường ${field} không khớp; không ghi đè.`,
      );
    }
  }
  if (!data.createdAt) {
    throw new Error(`Hồ sơ users/${uid} thiếu createdAt; không ghi đè.`);
  }
  return true;
}

function profileData(account, uid) {
  return {
    uid,
    fullName: account.fullName,
    email: account.email,
    role: account.role,
    status: 'active',
    createdAt: FieldValue.serverTimestamp(),
  };
}

async function seedAdmin(auth, firestore, account, password) {
  const adminReference = firestore.collection('system').doc('admin');
  const existingAdmin = await adminReference.get();

  if (existingAdmin.exists) {
    const uid = existingAdmin.data().uid;
    const user = await auth.getUser(uid);
    if (user.email !== account.email) {
      throw new Error(
        `Hệ thống đã có Admin UID ${uid}; script sẽ không tạo Admin thứ hai.`,
      );
    }
    const profile = await firestore.collection('users').doc(uid).get();
    assertMatchingProfile(profile, account, uid);
    return { email: account.email, created: false };
  }

  const authResult = await findOrCreateAuthUser(auth, account, password);
  const profileReference = firestore
    .collection('users')
    .doc(authResult.user.uid);

  try {
    await firestore.runTransaction(async (transaction) => {
      const adminSnapshot = await transaction.get(adminReference);
      const profileSnapshot = await transaction.get(profileReference);

      if (adminSnapshot.exists) {
        if (adminSnapshot.data().uid !== authResult.user.uid) {
          throw new Error('Admin duy nhất đã được khởi tạo bởi tiến trình khác.');
        }
      } else {
        transaction.create(adminReference, {
          uid: authResult.user.uid,
          email: account.email,
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      if (!assertMatchingProfile(profileSnapshot, account, authResult.user.uid)) {
        transaction.create(
          profileReference,
          profileData(account, authResult.user.uid),
        );
      }
    });
  } catch (error) {
    if (authResult.created) await auth.deleteUser(authResult.user.uid);
    throw error;
  }

  return { email: account.email, created: authResult.created };
}

async function seedRegularAccount(auth, firestore, account, password) {
  const authResult = await findOrCreateAuthUser(auth, account, password);
  const profileReference = firestore
    .collection('users')
    .doc(authResult.user.uid);

  try {
    await firestore.runTransaction(async (transaction) => {
      const profileSnapshot = await transaction.get(profileReference);
      if (!assertMatchingProfile(profileSnapshot, account, authResult.user.uid)) {
        transaction.create(
          profileReference,
          profileData(account, authResult.user.uid),
        );
      }
    });
  } catch (error) {
    if (authResult.created) await auth.deleteUser(authResult.user.uid);
    throw error;
  }

  return { email: account.email, created: authResult.created };
}

function saveNewCredentials(results, password) {
  const createdEmails = results
    .filter((result) => result.created)
    .map((result) => result.email);
  if (createdEmails.length === 0) return;

  const outputPath = path.resolve(__dirname, '..', 'DEMO_ACCOUNTS.local.md');
  if (fs.existsSync(outputPath)) {
    console.warn(
      'DEMO_ACCOUNTS.local.md đã tồn tại nên script không ghi đè mật khẩu.',
    );
    return;
  }

  const content = [
    '# Tài khoản demo nội bộ',
    '',
    'Mật khẩu dưới đây chỉ áp dụng cho các tài khoản được tạo mới trong lần seed này.',
    '',
    ...createdEmails.map((email) => `- ${email}`),
    '',
    `Mật khẩu: ${JSON.stringify(password)}`,
    '',
  ].join('\n');
  fs.writeFileSync(outputPath, content, { flag: 'wx', mode: 0o600 });
  console.log('Đã lưu thông tin đăng nhập mới vào DEMO_ACCOUNTS.local.md.');
}

async function main() {
  const { password, target } = readConfiguration();
  const app = initializeApp({
    credential: applicationDefault(),
    projectId: EXPECTED_PROJECT_ID,
  });

  try {
    const auth = getAuth(app);
    const firestore = getFirestore(app);
    const results = [];

    results.push(
      await seedAdmin(auth, firestore, DEMO_ACCOUNTS[0], password),
    );
    if (target === 'all') {
      for (const account of DEMO_ACCOUNTS.slice(1)) {
        results.push(
          await seedRegularAccount(auth, firestore, account, password),
        );
      }
    }

    saveNewCredentials(results, password);
    for (const result of results) {
      console.log(`${result.email}: ${result.created ? 'đã tạo' : 'đã tồn tại'}`);
    }
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(`Seed thất bại: ${error.message}`);
  process.exitCode = 1;
});
