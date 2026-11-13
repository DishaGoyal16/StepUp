// Runs the whole on-device E2E sequence (a -> e) in ONE app install / one process.
//
// Why one run: a fresh install generates a new native device id. The server only treats the FIRST registered device of
// an account as the reward device (a replacement phone takes over after `rewardDeviceTakeoverDays`), so a run that
// re-installs the app between files would see `isRewardDevice:false` and non-reward-eligible buckets. That is the
// designed behaviour, not a defect, but it means the files below must share one install.
//
//   .\integration_test\tools\run-e2e.ps1 -File e2e_full_test.dart -Reset -Watcher
import 'package:integration_test/integration_test.dart';

import 'e2e_a_auth_onboarding_tracking_test.dart' as a;
import 'e2e_b_sync_synthetic_test.dart' as b;
import 'e2e_c_second_user_test.dart' as c;
import 'e2e_d_admin_test.dart' as d;
import 'e2e_e_social_test.dart' as e;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  a.main();
  b.main();
  c.main();
  d.main();
  e.main();
}
