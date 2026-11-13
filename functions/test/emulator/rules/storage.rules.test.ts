import { assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';
import * as fs from 'fs';
import * as path from 'path';

let env: RulesTestEnvironment;
const BUCKET = 'gs://demo-stepup.appspot.com';

function hostPort(): { host: string; port: number } {
  const hp = (process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199').split(':');
  return { host: hp[0], port: Number(hp[1]) };
}

const st = {
  alice: () => env.authenticatedContext('alice', { email: 'alice@thapar.edu', email_verified: true }).storage(BUCKET),
  bob: () => env.authenticatedContext('bob', { email: 'bob@thapar.edu', email_verified: true }).storage(BUCKET),
  outsider: () => env.authenticatedContext('alice', { email: 'alice@gmail.com', email_verified: true }).storage(BUCKET),
  unverified: () => env.authenticatedContext('alice', { email: 'alice@thapar.edu', email_verified: false }).storage(BUCKET),
  anon: () => env.unauthenticatedContext().storage(BUCKET),
};

const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);

beforeAll(async () => {
  const { host, port } = hostPort();
  env = await initializeTestEnvironment({
    projectId: 'demo-stepup',
    storage: { rules: fs.readFileSync(path.join(__dirname, '../../../../storage.rules'), 'utf8'), host, port },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (c) => {
    await uploadBytes(ref(c.storage(BUCKET), 'profilePhotos/alice/seed.png'), png, { contentType: 'image/png' });
  });
});

describe('profile photo storage rules', () => {
  test('owner uploads an image to their own folder', async () => {
    await assertSucceeds(uploadBytes(ref(st.alice(), 'profilePhotos/alice/me.png'), png, { contentType: 'image/png' }));
    await assertSucceeds(uploadBytes(ref(st.alice(), 'profilePhotos/alice/me2.jpg'), png, { contentType: 'image/jpeg' }));
  });

  test("a student cannot write into someone else's folder", async () => {
    await assertFails(uploadBytes(ref(st.bob(), 'profilePhotos/alice/evil.png'), png, { contentType: 'image/png' }));
  });

  test('non-image content types are rejected', async () => {
    await assertFails(uploadBytes(ref(st.alice(), 'profilePhotos/alice/x.pdf'), png, { contentType: 'application/pdf' }));
    await assertFails(uploadBytes(ref(st.alice(), 'profilePhotos/alice/x.html'), png, { contentType: 'text/html' }));
    await assertFails(uploadBytes(ref(st.alice(), 'profilePhotos/alice/x.svg'), png, { contentType: 'image/svg+xml' }));
  });

  test('files over 2 MB are rejected; exactly 2 MB is accepted', async () => {
    await assertFails(uploadBytes(ref(st.alice(), 'profilePhotos/alice/big.png'), new Uint8Array(2 * 1024 * 1024 + 1), { contentType: 'image/png' }));
    await assertSucceeds(uploadBytes(ref(st.alice(), 'profilePhotos/alice/ok.png'), new Uint8Array(2 * 1024 * 1024), { contentType: 'image/png' }));
  });

  test('paths outside profilePhotos/{uid}/{file} are denied', async () => {
    await assertFails(uploadBytes(ref(st.alice(), 'other/alice/x.png'), png, { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st.alice(), 'profilePhotos/x.png'), png, { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st.alice(), 'profilePhotos/alice/sub/x.png'), png, { contentType: 'image/png' }));
  });

  test('eligible users can read photos; anonymous, non-thapar and unverified cannot', async () => {
    await assertSucceeds(getBytes(ref(st.bob(), 'profilePhotos/alice/seed.png')));
    await assertFails(getBytes(ref(st.anon(), 'profilePhotos/alice/seed.png')));
    await assertFails(getBytes(ref(st.outsider(), 'profilePhotos/alice/seed.png')));
    await assertFails(getBytes(ref(st.unverified(), 'profilePhotos/alice/seed.png')));
  });

  test('non-thapar / unverified / anonymous cannot upload even to a matching uid folder', async () => {
    await assertFails(uploadBytes(ref(st.outsider(), 'profilePhotos/alice/o.png'), png, { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st.unverified(), 'profilePhotos/alice/u.png'), png, { contentType: 'image/png' }));
    await assertFails(uploadBytes(ref(st.anon(), 'profilePhotos/alice/a.png'), png, { contentType: 'image/png' }));
  });

  test('only the owner can delete', async () => {
    await assertFails(deleteObject(ref(st.bob(), 'profilePhotos/alice/seed.png')));
    await assertSucceeds(deleteObject(ref(st.alice(), 'profilePhotos/alice/seed.png')));
  });
});
