import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import 'bets_environment.dart';

/// Providers owned by the bets feature. The screens create their own
/// view-models (they need the signed-in uid and route parameters).
List<SingleChildWidget> betsProviders(AppDependencies deps) => [
      Provider<BetsEnvironment>.value(value: BetsEnvironment.of(deps)),
    ];
