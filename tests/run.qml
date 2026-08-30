// Test entry point: qml6 tests/run.qml
import QtQml
import "security-tests.mjs" as T

QtObject {
  Component.onCompleted: function() {
    var fails = 0
    try {
      fails = T.runAll()
    } catch (e) {
      console.log("HARNESS ERROR:", e.message)
      fails = 1
    }
    Qt.quit()
  }
}