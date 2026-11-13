/** Integration tests; run through `firebase emulators:exec` (see package.json). */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  forceExit: true,
  roots: ['<rootDir>/test/emulator'],
  testMatch: ['**/*.test.ts'],
  testTimeout: 60000,
  transform: { '^.+\.ts$': ['ts-jest', { tsconfig: 'tsconfig.json', diagnostics: { warnOnly: false } }] },
};
