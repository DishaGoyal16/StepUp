package edu.thapar.stepup

import edu.thapar.stepup.steps.StepEnginePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var stepEngine: StepEnginePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        stepEngine = StepEnginePlugin(applicationContext).also { it.register(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stepEngine?.dispose()
        stepEngine = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
