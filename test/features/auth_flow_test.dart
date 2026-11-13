import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stepup/domain/profile_draft.dart';
import 'package:stepup/domain/profile_enums.dart';

import '../support/harness.dart';

Finder field(int i) => find.byType(TextFormField).at(i);
FilledButton filled(WidgetTester t, String label) =>
    t.widget<FilledButton>(find.widgetWithText(FilledButton, label));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('login screen', () {
    testWidgets('signed-out users land on login with the welcome text', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester);
      expect(find.text('Welcome to StepUp'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.text('StepUp'), findsOneWidget, reason: 'logo name');
    });

    testWidgets('Login stays disabled until a valid @thapar.edu email and a password are entered',
        (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester);

      expect(filled(tester, 'Login').onPressed, isNull, reason: 'empty form');

      await tester.enterText(field(0), 'someone@gmail.com');
      await tester.enterText(field(1), 'Password1');
      await tester.pump();
      expect(filled(tester, 'Login').onPressed, isNull, reason: 'wrong domain');
      expect(find.text('Use your @thapar.edu email address'), findsOneWidget);

      await tester.enterText(field(0), 'someone@thapar.edu.evil.com');
      await tester.pump();
      expect(filled(tester, 'Login').onPressed, isNull, reason: 'lookalike domain');

      await tester.enterText(field(0), 'someone@thapar.edu');
      await tester.enterText(field(1), '');
      await tester.pump();
      expect(filled(tester, 'Login').onPressed, isNull, reason: 'no password');

      await tester.enterText(field(1), 'x');
      await tester.pump();
      expect(filled(tester, 'Login').onPressed, isNotNull);
    });

    testWidgets('wrong credentials show a friendly error', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      h.auth.seedAccount(email: kStudentEmail, signIn: false);
      await h.pumpApp(tester);
      await tester.enterText(field(0), kStudentEmail);
      await tester.enterText(field(1), 'WrongPass9');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await settle(tester);
      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.text('Welcome to StepUp'), findsOneWidget, reason: 'still on login');
    });

    testWidgets('network failure shows a network message', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      h.auth.seedAccount(email: kStudentEmail, signIn: false);
      await h.pumpApp(tester);
      await tester.enterText(field(0), kStudentEmail);
      await tester.enterText(field(1), 'Password1');
      await tester.pump();
      h.auth.failNextWithCode = 'network-request-failed';
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await settle(tester);
      expect(find.textContaining('Network problem'), findsOneWidget);
    });

    testWidgets('verified user with a profile goes straight to Home', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      final u = h.auth.seedAccount(email: kStudentEmail, signIn: false);
      h.profiles.setProfile(makeProfile(u.uid));
      await h.pumpApp(tester);
      await tester.enterText(field(0), '  ${kStudentEmail.toUpperCase()} ');
      await tester.enterText(field(1), 'Password1');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await settle(tester);
      expect(find.text('Hi, Aarav'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('Google button is hidden unless GOOGLE_SIGN_IN_ENABLED', (tester) async {
      useTallView(tester);
      final off = Harness.create();
      await off.pumpApp(tester);
      expect(find.text('Continue with Google'), findsNothing);

      final on = Harness.create(googleEnabled: true);
      await on.pumpApp(tester);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.textContaining('Only @thapar.edu'), findsOneWidget);
    });

    testWidgets('Register and Forgot password navigate', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester);
      await tester.tap(find.text('Forgot password?'));
      await settle(tester);
      expect(find.text('Send reset link'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text('Register'));
      await settle(tester);
      expect(find.text('Create your account'), findsOneWidget);
    });
  });

  group('forgot password', () {
    testWidgets('sends a reset mail for a valid address, button disabled otherwise', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester);
      await tester.tap(find.text('Forgot password?'));
      await settle(tester);
      expect(filled(tester, 'Send reset link').onPressed, isNull);
      await tester.enterText(field(0), 'a@gmail.com');
      await tester.pump();
      expect(filled(tester, 'Send reset link').onPressed, isNull);
      await tester.enterText(field(0), 'a@thapar.edu');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
      await settle(tester);
      expect(h.auth.passwordResetsSentTo, ['a@thapar.edu']);
      expect(find.textContaining('If an account exists'), findsOneWidget);
    });
  });

  group('registration', () {
    Future<void> openRegister(WidgetTester tester, Harness h) async {
      await h.pumpApp(tester);
      await tester.tap(find.text('Register'));
      await settle(tester);
    }

    Future<void> fillAccount(WidgetTester tester, {String email = 'new.student@thapar.edu'}) async {
      await tester.enterText(field(0), 'New Student');
      await tester.enterText(field(1), email);
      await tester.enterText(field(2), 'Password1');
      await tester.enterText(field(3), 'Password1');
      await tester.pump();
    }

    testWidgets('a non-thapar address is blocked on step 1', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await openRegister(tester, h);
      await fillAccount(tester, email: 'student@gmail.com');
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Use your @thapar.edu email address'), findsOneWidget);
      expect(find.textContaining('Step 1 of 2'), findsOneWidget);
      expect(h.auth.currentUser, isNull, reason: 'no account created');
    });

    testWidgets('look-alike and sub-domain addresses are blocked too', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await openRegister(tester, h);
      for (final bad in ['a@thapar.edu.evil.com', 'a@mail.thapar.edu', 'a@thapar.com']) {
        await fillAccount(tester, email: bad);
        await tester.tap(find.text('Next'));
        await settle(tester);
        expect(find.textContaining('Step 1 of 2'), findsOneWidget, reason: bad);
      }
    });

    testWidgets('mismatching passwords and weak passwords are flagged', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await openRegister(tester, h);
      await tester.enterText(field(0), 'New Student');
      await tester.enterText(field(1), 'new@thapar.edu');
      await tester.enterText(field(2), 'weak');
      await tester.enterText(field(3), 'different');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('full flow: account -> profile answers -> verification screen, answers kept locally',
        (tester) async {
      useTallView(tester, height: 5000);
      final h = Harness.create();
      await openRegister(tester, h);
      await fillAccount(tester);
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.textContaining('Step 2 of 2'), findsOneWidget);

      // Submitting with nothing chosen shows the inline errors.
      await tester.tap(find.text('Create account'));
      await settle(tester);
      expect(find.text('Choose your hostel'), findsOneWidget);
      expect(find.text('Choose your fitness level'), findsOneWidget);
      expect(find.text('Pick at least one sport'), findsOneWidget);
      expect(h.auth.currentUser, isNull);

      // The hostel list falls back to the built-in directory (not signed in).
      expect(find.textContaining('built-in hostel list'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hostel-dropdown')));
      await settle(tester);
      expect(find.text('Hostels'), findsWidgets);
      expect(find.text("Girls' hostels"), findsWidgets);
      expect(find.text('Agira Hall (Previously Hostel-A)'), findsWidgets);
      await tester.tap(find.text('Vasudha Hall - Block E (Previously Hostel-E)').last);
      await settle(tester);
      expect(find.text('Block E'), findsOneWidget, reason: 'block comes from the hostel');

      await tester.tap(find.text('Intermediate'));
      await tester.tap(find.text('Cricket'));
      await tester.tap(find.text('Yoga'));
      await tester.tap(find.text('Evening'));
      await tester.tap(find.text('Group'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('activity-dropdown')));
      await settle(tester);
      await tester.tap(find.text('Cricket').last);
      await settle(tester);

      await tester.tap(find.text('Create account'));
      await settle(tester);

      // account exists, verification mail sent, router moved to the inbox screen
      expect(h.auth.currentUser?.email, 'new.student@thapar.edu');
      expect(h.auth.currentUser?.emailVerified, isFalse);
      expect(h.auth.verificationEmailsSent, 1);
      expect(find.text('Check your inbox'), findsOneWidget);

      // step-2 answers were saved on the device for onboarding
      final draft = await h.drafts.load(h.auth.currentUser!.uid);
      expect(draft, isNotNull);
      expect(draft!.displayName, 'New Student');
      expect(draft.hostelId, 'vasudha-e');
      expect(draft.block, 'E');
      expect(draft.fitnessLevel, FitnessLevel.intermediate);
      expect(draft.sportsInterests, containsAll(['Cricket', 'Yoga']));
      expect(draft.preferredActivity, 'Cricket');
      expect(draft.preferredTime, PreferredTime.evening);
      expect(draft.buddyType, BuddyType.group);
      // nothing was sent to the profile backend yet
      expect(h.profiles.createCalls, 0);
    });

    testWidgets('an existing account shows the duplicate-account message', (tester) async {
      useTallView(tester, height: 5000);
      final h = Harness.create();
      h.auth.seedAccount(email: 'new.student@thapar.edu', signIn: false);
      await openRegister(tester, h);
      await fillAccount(tester);
      await tester.tap(find.text('Next'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('hostel-dropdown')));
      await settle(tester);
      await tester.tap(find.text('Agira Hall (Previously Hostel-A)').last);
      await settle(tester);
      await tester.tap(find.text('Beginner'));
      await tester.tap(find.text('Walking'));
      await tester.tap(find.text('Morning'));
      await tester.tap(find.text('Either'));
      await tester.tap(find.byKey(const ValueKey('activity-dropdown')));
      await settle(tester);
      await tester.tap(find.text('Walking').last);
      await settle(tester);
      await tester.tap(find.text('Create account'));
      await settle(tester);
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.text('Check your inbox'), findsNothing);
    });
  });

  group('verification screen', () {
    testWidgets('unverified user only sees the verification screen with its three actions',
        (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, verified: false);
      await h.pumpApp(tester, initialLocation: '/home');
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining(kStudentEmail), findsOneWidget);
      expect(find.text('I verified'), findsOneWidget);
      expect(find.text('Resend verification email'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.textContaining('only confirms that you can read'), findsOneWidget);
    });

    testWidgets('Resend sends a mail and is rate limited', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, verified: false);
      await h.pumpApp(tester);
      await tester.tap(find.text('Resend verification email'));
      await settle(tester);
      expect(h.auth.verificationEmailsSent, 1);
      expect(find.textContaining('Verification email sent'), findsOneWidget);

      await tester.tap(find.text('Resend verification email'));
      await settle(tester);
      expect(h.auth.verificationEmailsSent, 1, reason: 'cooldown');
      expect(find.textContaining('Please wait'), findsOneWidget);

      h.clock.advance(const Duration(seconds: 31));
      await tester.tap(find.text('Resend verification email'));
      await settle(tester);
      expect(h.auth.verificationEmailsSent, 2);
    });

    testWidgets('"I verified" before verifying keeps the user here; after verifying moves on',
        (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, verified: false);
      await h.pumpApp(tester);
      await tester.tap(find.text('I verified'));
      await settle(tester);
      expect(find.textContaining('Not verified yet'), findsOneWidget);
      expect(find.text('Check your inbox'), findsOneWidget);

      h.auth.simulateEmailVerified();
      await tester.tap(find.text('I verified'));
      await settle(tester);
      // verified but no profile yet -> onboarding
      expect(find.text('Finish setting up'), findsOneWidget);
    });

    testWidgets('polling notices verification by itself', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, verified: false);
      await h.pumpApp(tester);
      h.auth.simulateEmailVerified();
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(find.text('Finish setting up'), findsOneWidget);
    });

    testWidgets('Sign out returns to login', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, verified: false);
      await h.pumpApp(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.text('Welcome to StepUp'), findsOneWidget);
      expect(h.auth.currentUser, isNull);
    });
  });

  group('onboarding', () {
    testWidgets('verified user without a profile is sent to onboarding and cannot reach Home',
        (tester) async {
      useTallView(tester, height: 5000);
      final h = Harness.create(signedIn: true, verified: true);
      await h.pumpApp(tester, initialLocation: '/home');
      expect(find.text('Finish setting up'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('answers saved during registration are restored and createProfile is called',
        (tester) async {
      useTallView(tester, height: 5000);
      final h = Harness.create(signedIn: true, verified: true);
      await h.drafts.save(
        h.user!.uid,
        const ProfileDraft(
          displayName: 'Aarav Sharma',
          hostelId: 'agira',
          fitnessLevel: FitnessLevel.beginner,
          sportsInterests: ['Running', 'Yoga'],
          preferredActivity: 'Running',
          preferredTime: PreferredTime.morning,
          buddyType: BuddyType.both,
          bio: 'Early bird',
          photoLocalPath: '/nonexistent/photo.jpg',
        ),
      );
      await h.pumpApp(tester);
      await settle(tester);
      expect(find.textContaining('We kept the answers'), findsOneWidget);
      expect(find.text('Early bird'), findsOneWidget);

      await tester.tap(find.text('Finish'));
      await settle(tester);

      expect(h.profiles.createCalls, 1);
      expect(h.profiles.lastDraft?.hostelId, 'agira');
      expect(h.profiles.lastDraft?.sportsInterests, ['Running', 'Yoga']);
      expect(h.profiles.lastPhotoUrl, isNotNull, reason: 'optional photo was uploaded');
      expect(await h.drafts.load(h.user!.uid), isNull, reason: 'draft cleared after success');
      expect(find.text('Hi, Aarav'), findsOneWidget, reason: 'router moved to Home');
    });

    testWidgets('empty onboarding shows validation errors and does not call the backend', (tester) async {
      useTallView(tester, height: 5000);
      final h = Harness.create(signedIn: true, verified: true);
      await h.pumpApp(tester);
      await settle(tester);
      await tester.tap(find.text('Finish'));
      await settle(tester);
      expect(find.text('Choose your hostel'), findsOneWidget);
      expect(h.profiles.createCalls, 0);
    });
  });

  group('router guard through the real app', () {
    testWidgets('signed-out deep link to /home goes to login', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester, initialLocation: '/home');
      expect(find.text('Welcome to StepUp'), findsOneWidget);
    });

    testWidgets('non-admin cannot open /admin', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      await h.pumpApp(tester, initialLocation: '/admin');
      expect(find.text('Hi, Aarav'), findsOneWidget);
    });

    testWidgets('admin can open /admin', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true, role: 'admin');
      await h.pumpApp(tester, initialLocation: '/admin');
      final ctx = tester.element(find.byType(Scaffold).first);
      expect(GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.path, '/admin');
      expect(find.text('Hi, Aarav'), findsNothing);
    });
  });
}
