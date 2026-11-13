import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/functions/callables.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/profile/fake_photo_services.dart';
import 'package:stepup/domain/profile_enums.dart';
import 'package:stepup/domain/user_profile.dart';
import 'package:stepup/features/profile/edit_profile_view_model.dart';

import '../../support/harness.dart';
import 'profile_test_support.dart';

void main() {
  group('EditProfileViewModel', () {
    late FakeFunctionsClient fn;
    late FakePhotoPicker picker;
    late FakePhotoUploader uploader;
    late UserProfile profile;
    late EditProfileViewModel vm;

    setUp(() {
      fn = FakeFunctionsClient()..on('updateProfile', (_) => {'ok': true});
      picker = FakePhotoPicker();
      uploader = FakePhotoUploader();
      profile = makeProfile('u1');
      vm = EditProfileViewModel(
        profile: profile,
        callables: Callables(fn),
        picker: picker,
        uploader: uploader,
      );
    });

    tearDown(() => vm.dispose());

    test('starts from the stored profile with no changes', () {
      expect(vm.displayName, 'Aarav Sharma');
      expect(vm.dailyGoalText, '10000');
      expect(vm.hasChanges, isFalse);
      expect(vm.buildChanges(), isEmpty);
    });

    test('save with no edits does nothing', () async {
      expect(await vm.save(), SaveOutcome.noChanges);
      expect(fn.calls, isEmpty);
    });

    test('only changed, permitted fields are sent through updateProfile', () async {
      vm.setDisplayName('  Aarav S  ');
      vm.setBio('Early runner');
      vm.setDailyGoalText('12000');
      vm.setFitnessLevel(FitnessLevel.advanced);
      vm.toggleSport('Cricket');
      vm.setPreferredTime(PreferredTime.evening);
      vm.setBuddyType(BuddyType.group);
      vm.toggleGoal('Stay active');
      vm.toggleDay('MON');
      vm.setPreferredActivity('Cricket');
      expect(await vm.save(), SaveOutcome.success);
      final sent = fn.callsTo('updateProfile').single.params;
      expect(sent, {
        'displayName': 'Aarav S',
        'bio': 'Early runner',
        'dailyGoal': 12000,
        'fitnessLevel': 'ADVANCED',
        'sportsInterests': ['Running', 'Cricket'],
        'preferredActivity': 'Cricket',
        'preferredTime': 'EVENING',
        'goals': ['Stay active'],
        'availability': ['MON'],
        'buddyType': 'GROUP',
      });
      for (final forbidden in ['hostelId', 'block', 'pointsBalance', 'pointsReserved', 'status', 'role', 'email']) {
        expect(sent.containsKey(forbidden), isFalse, reason: '$forbidden is never editable here');
      }
    });

    test('unchanged fields are not sent', () async {
      vm.setBio('Hello');
      await vm.save();
      expect(fn.callsTo('updateProfile').single.params, {'bio': 'Hello'});
    });

    test('validation: name, bio length, daily goal range, sports', () async {
      expect(EditProfileViewModel.validateName(''), isNotNull);
      expect(EditProfileViewModel.validateName('A'), isNotNull);
      expect(EditProfileViewModel.validateName('A' * 51), isNotNull);
      expect(EditProfileViewModel.validateName('Aa'), isNull);
      expect(EditProfileViewModel.validateBio('x' * 161), isNotNull);
      expect(EditProfileViewModel.validateBio('x' * 160), isNull);
      expect(EditProfileViewModel.validateDailyGoal('999'), isNotNull);
      expect(EditProfileViewModel.validateDailyGoal('50001'), isNotNull);
      expect(EditProfileViewModel.validateDailyGoal('abc'), isNotNull);
      expect(EditProfileViewModel.validateDailyGoal('1000'), isNull);
      expect(EditProfileViewModel.validateDailyGoal('50000'), isNull);

      vm.setDailyGoalText('500');
      expect(await vm.save(), SaveOutcome.invalid);
      expect(vm.error, contains('between'));
      vm.setDailyGoalText('10000');
      vm.toggleSport('Running'); // deselect the only sport
      expect(await vm.save(), SaveOutcome.invalid);
      expect(vm.error, 'Pick at least one sport');
      expect(fn.calls, isEmpty);
    });

    test('a server error keeps the form and shows the server message', () async {
      vm.setBio('New bio');
      fn.failNext(
        'updateProfile',
        AppException.fromCallable(code: 'invalid-argument', message: 'Bio contains blocked words.'),
      );
      expect(await vm.save(), SaveOutcome.failed);
      expect(vm.error, 'Bio contains blocked words.');
      expect(vm.bio, 'New bio');
      expect(vm.saving, isFalse);
      // editing clears the error and a retry succeeds
      vm.setBio('Other bio');
      expect(vm.error, isNull);
      expect(await vm.save(), SaveOutcome.success);
    });

    test('a picked photo is uploaded first and its URL sent as photoUrl', () async {
      picker.path = '/tmp/me.jpg';
      await vm.pickPhoto();
      expect(vm.pickedPhotoPath, '/tmp/me.jpg');
      expect(vm.hasChanges, isTrue);
      expect(await vm.save(), SaveOutcome.success);
      expect(uploader.uploads.single, (uid: 'u1', localPath: '/tmp/me.jpg'));
      expect(
        fn.callsTo('updateProfile').single.params['photoUrl'],
        'https://fake.storage/profilePhotos/u1/avatar.jpg',
      );
    });

    test('a cancelled pick changes nothing', () async {
      picker.path = null;
      await vm.pickPhoto();
      expect(vm.pickedPhotoPath, isNull);
      expect(vm.hasChanges, isFalse);
    });

    test('upload failure: error shown, updateProfile NOT called', () async {
      picker.path = '/tmp/me.jpg';
      uploader.shouldFail = true;
      await vm.pickPhoto();
      expect(await vm.save(), SaveOutcome.failed);
      expect(vm.error, contains('upload your photo'));
      expect(fn.callsTo('updateProfile'), isEmpty);
    });

    test('removing an existing photo sends photoUrl: null', () async {
      final withPhoto = rebuildProfile(profile, photoUrl: 'https://x/y.jpg');
      final v = EditProfileViewModel(
        profile: withPhoto,
        callables: Callables(fn),
        picker: picker,
        uploader: uploader,
      );
      expect(v.hasPhoto, isTrue);
      v.clearPhoto();
      expect(v.hasPhoto, isFalse);
      expect(await v.save(), SaveOutcome.success);
      final sent = fn.callsTo('updateProfile').single.params;
      expect(sent.containsKey('photoUrl'), isTrue);
      expect(sent['photoUrl'], isNull);
      v.dispose();
    });
  });

  group('EditProfileScreen', () {
    testWidgets('shows the current values and a read-only hostel', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/edit');
      expect(find.widgetWithText(TextFormField, 'Aarav Sharma'), findsOneWidget);
      expect(find.text('Agira Hall'), findsOneWidget);
      expect(find.text('Hostel changes are not available in the app.'), findsOneWidget);
      expect(find.text('Hostel'), findsOneWidget);
      // hostel is not an editable field
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget, reason: 'only preferred activity');
    });

    testWidgets('saving a change calls updateProfile, shows feedback and returns to the profile', (tester) async {
      final env = ProfileEnv();
      env.functions.on('updateProfile', (_) => {'ok': true});
      await env.pump(tester, initial: '/profile/edit');
      await tester.enterText(find.byKey(const ValueKey('field-bio')), 'Love early walks');
      await tester.pump();
      await tapVisible(tester, find.text('Save changes'));
      expect(env.functions.callsTo('updateProfile').single.params, {'bio': 'Love early walks'});
      expect(find.text('Profile updated'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget, reason: 'back on the profile tab');
    });

    testWidgets('invalid daily goal is blocked with a message and nothing is sent', (tester) async {
      final env = ProfileEnv();
      env.functions.on('updateProfile', (_) => {'ok': true});
      await env.pump(tester, initial: '/profile/edit');
      await tester.enterText(find.byKey(const ValueKey('field-daily-goal')), '500');
      await tester.pump();
      await tapVisible(tester, find.text('Save changes'));
      expect(find.textContaining('Choose between 1000 and 50000'), findsOneWidget);
      expect(env.functions.callsTo('updateProfile'), isEmpty);
    });

    testWidgets('a name that is too short is rejected', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/edit');
      await tester.enterText(find.byKey(const ValueKey('field-name')), 'A');
      await tester.pump();
      await tapVisible(tester, find.text('Save changes'));
      expect(find.text('Name is too short'), findsOneWidget);
      expect(env.functions.callsTo('updateProfile'), isEmpty);
    });

    testWidgets('a server error is shown and the form stays open', (tester) async {
      final env = ProfileEnv();
      env.functions.failNext('updateProfile', AppException.fromCallable(code: 'unavailable'));
      await env.pump(tester, initial: '/profile/edit');
      await tester.enterText(find.byKey(const ValueKey('field-bio')), 'Hi');
      await tester.pump();
      await tapVisible(tester, find.text('Save changes'));
      expect(find.byKey(const ValueKey('edit-error')), findsOneWidget);
      expect(find.textContaining('Network problem'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('chips edit level, sports, time and availability', (tester) async {
      final env = ProfileEnv();
      env.functions.on('updateProfile', (_) => {'ok': true});
      await env.pump(tester, initial: '/profile/edit');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Advanced'));
      await tapVisible(tester, find.widgetWithText(FilterChip, 'Cricket'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Evening'));
      await tapVisible(tester, find.widgetWithText(FilterChip, 'Tue'));
      await tapVisible(tester, find.text('Save changes'));
      final sent = env.functions.callsTo('updateProfile').single.params;
      expect(sent['fitnessLevel'], 'ADVANCED');
      expect(sent['sportsInterests'], ['Running', 'Cricket']);
      expect(sent['preferredTime'], 'EVENING');
      expect(sent['availability'], ['TUE']);
    });

    testWidgets('choosing a photo uploads it through the injected uploader', (tester) async {
      final env = ProfileEnv();
      (env.deps.photoPicker as FakePhotoPicker).path = '/tmp/new.jpg';
      env.functions.on('updateProfile', (_) => {'ok': true});
      await env.pump(tester, initial: '/profile/edit');
      await tapVisible(tester, find.text('Add photo'));
      expect(find.text('New photo selected'), findsOneWidget);
      await tapVisible(tester, find.text('Save changes'));
      final uploads = (env.deps.photoUploader as FakePhotoUploader).uploads;
      expect(uploads.single.localPath, '/tmp/new.jpg');
      expect(env.functions.callsTo('updateProfile').single.params['photoUrl'], startsWith('https://'));
    });

    testWidgets('leaving with unsaved edits asks for confirmation', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester);
      await tester.tap(find.text('Edit profile'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('field-bio')), 'Unsaved');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      expect(find.text('Save changes'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(find.text('Save changes'), findsNothing);
      expect(env.functions.callsTo('updateProfile'), isEmpty);
    });
  });
}

